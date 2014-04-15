$stdout.sync = $stderr.sync = true

require "cgi"
require "excon"
require "multi_json"
require "sinatra"
require "omniauth"
require "omniauth-heroku"
require "base64"
require "haml"
require "json"

use Rack::Session::Cookie, :secret => ENV["COOKIE_SECRET"]
use OmniAuth::Builder do
  provider :heroku, ENV["HEROKU_OAUTH_ID"], ENV["HEROKU_OAUTH_SECRET"], { scope: "global" }
end

# by default, the deployer is setup for a specific app.json
get "/" do
   if !session[:heroku_oauth_token]
   <<-HTML
   To deploy this app in your Heroku account, please first <a href='/auth/heroku'>Sign in with Heroku</a>
   HTML
   else
    installedby = "personalization-factory" # see if there is a way to get this from the env

     # a better way might be to read this from a file
    session[:aname] = "Personalized Clock"
    session[:desc] = "A simple clock that greets you by name, everytime!"
    session[:configvar_defaults] = {"FIRST_NAME"=>"World","LAST_NAME"=>"","INSTALLED_BY"=>installedby}
    session[:addons] = ["heroku-postgresql","papertrail"]
    session[:success_url] = "/clock/currenttime"
    session[:website] = "https://github.com/balansubr/SampleTimeApp"
    session[:source_url] = "https://github.com/balansubr/SampleTimeApp/tarball/master/"
    haml :form, :locals => {:app => session[:aname], 
                            :desc => session[:desc], 
                            :adds => session[:addons], 
                            :vars => session[:configvar_defaults],
                            :website => session[:website],
                            :source_url => session[:source_url]
                            }  
   end
end

# you can also post an app.json to the deployer
post "/" do
   params = JSON.parse(request.env["rack.input"].read)
   processJson(params)

   haml :form, :locals => {:app => session[:name], 
                            :desc => session[:description], 
                            :adds => session[:addons], 
                            :vars => session[:configvar_defaults],
                            :website => session[:website],
                            :source_url => session[:source_url]
                            }  
end

def processJson(input_json)
  session[:source_url] = input_json["source_url"] # this is not part of the app.json schema but needs to be passed in anyway
  session[:name] = input_json["name"] || "No name"
  session[:description] = input_json["description"] || ""
  
  configvars_defaults = Hash.new # this will hold the key and default value for now
  allvars = input_json["env"]
  allvars.each do | var, var_details |
    if(var_details["generator"]=="") # if something is going to be generated exclude it from the form
      configvars_defaults[:var] = var_details["default"] || ""
    end
  end
  session[:configvar_defaults] = configvars_defaults
  session[:addons] = input_json["addons"] 
  session[:success_url] = input_json["urls"]["success"]
  session[:website] = input_json["urls"]["website"]
end

get "/deploy" do
  
  sourceurl = params[:source_url] || ""
  params.delete("source_url")  
  envStr = ''
  dochop = false
  params.each do |var_name, var_value|
    envStr = envStr + '"' + var_name + '":"' + var_value + '",'
    dochop = true
  end
  if(dochop) 
     envStr.chop!   
  end

=begin    
  firstname = params[:firstname] || "Not specified"
  lastname = params[:lastname] || "Not specified"
  sourceurl = params[:source_url] || "Not specified"
  installedby = "personalized-clock-factory"
  
  body = '{"source_blob": { "url":"'+ sourceurl+ '"}, "env": { "INSTALLED_BY":"'+ installedby+'", "LAST_NAME":"'+ lastname+'", "FIRST_NAME":"'+ firstname+'"} }'
=end

  body = '{"source_blob": { "url":"'+ sourceurl+ '"}, "env": { ' + envStr + '} }'
  
  puts body
  
  res = Excon.post("https://nyata.herokuapp.com/app-setups",
                  :body => body,
                  :headers => { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}", "Content-Type" => "application/json"}
                 )
                 
  # "Authorization" => "Bearer #{session[:heroku_oauth_token]}"
  # "Authorization" => "Basic OjIzZjFjYzY0LWRmMjItNDM2OS05OWMxLTExYjNkYmYyZWVjNg=="
  
  id = MultiJson.decode(res.body)["id"]
  
  if(id=="invalid_params" || id=="")
      message = MultiJson.decode(res.body)["message"]
      body message
  else
    session[:setupid] = id
    session[:appname] = MultiJson.decode(res.body)["app"]["name"]
    redirect "/status"
  end  
end

get "/status" do
  # can't do much status without the setup id
  if !session[:setupid] 
      redirect "/deploy"
  end
 
  haml :status, :locals => {:appname => session[:appname]}
end

get "/overall-status" do
  # get the overall status
  statuscall = Excon.new("https://nyata.herokuapp.com",
      headers: { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}" })
  res = statuscall.get(path: "/app-setups/"+session[:setupid])
  newstatus = MultiJson.decode(res.body)["status"] 
  id = MultiJson.decode(res.body)["id"]

  statusmsg = newstatus
  if(newstatus == "failed")
    statusmsg = "Failed ["+MultiJson.decode(res.body["failure_message"])+"]";
  end
  if(newstatus == "succeeded")
    statusmsg = "Link to your own clock: <a href=\"http://" + session[:appname] + ".herokuapp.com" + session[:success_url]+ ">Click here</a>"
  end
  
  body statusmsg
end

get "/setup-status" do
    # get the overall status
    statuscall = Excon.new("https://nyata.herokuapp.com",
                    headers: { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}" })
    res = statuscall.get(path: "/app-setups/"+session[:setupid])
    newstatus = MultiJson.decode(res.body)["status"] || "Not Available"
 

    overallstatus = "Setup status: " + newstatus + "<br><br>" + "Detailed status: <br>" + JSON.pretty_generate(res.body) + "<br><br>"
    body overallstatus
end

get "/build-status" do
    # get the build status
    buildstatus = "Build not started"
    buildstatusdetails = "Not available"
    if(!session[:buildid])
        # get the overall status
        statuscall = Excon.new("https://nyata.herokuapp.com",
                                headers: { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}" })
        res = statuscall.get(path: "/app-setups/"+session[:setupid])
        buildid = MultiJson.decode(res.body)["build"]["id"]
        session[:buildid] = buildid
    end
    if(session[:buildid])
        buildcall = Excon.new("https://api.heroku.com",
                        headers: { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}",
                                   "Accept" => "application/vnd.heroku+json; version=3"  })
        buildcallpath = "/apps/" + session[:appname] + "/builds/" + session[:buildid] + "/result"
        buildres = buildcall.get(path: buildcallpath)
        buildstatusdetails = JSON.pretty_generate(buildres.body) 
        buildstatus = MultiJson.decode(buildres.body)["build"]["status"]
    end
    
    body "Build status: " + buildstatus + "<br><br>" + "Detailed status: <br>" + buildstatusdetails + "<br><br>"
end


get "/auth/heroku/callback" do
  session[:heroku_oauth_token] =
    request.env["omniauth.auth"]["credentials"]["token"]
  redirect "/"
end

get "/getting-started" do
  <<-HTML
    Try this app:
    <ol>
      <li>Go to the provisioned app's URL</li>
      <li>Log into a different heroku ID</li>
      <li>See the email address</li>
    </ol>
  HTML
end