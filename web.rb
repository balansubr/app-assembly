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

# by default, this deployer is setup for a specific app.json and source url but parameters can be passed in to specify them
get "/" do
   puts "This is what I got for params:"
   puts params
   
   # if this is a direct call, then params will have some values and we should update the session
   if(params[:src])
     session[:source_url] = params[:src] || "https://github.com/balansubr/SampleTimeApp/tarball/master/"
     session[:appjsonfile] = params[:json] || "SampleTimeApp_app.json"
   else # this means that we got redirected here from the ouath call back
     if(!session[:source_url]) # this shouldn't happen because we already stored the params but if it does then use defaults
        session[:source_url] = "https://github.com/balansubr/SampleTimeApp/tarball/master/"
        session[:appjsonfile] = "SampleTimeApp_app.json"
      end
   end
   puts "source_url in session=" + session[:source_url]
   puts "appjsonfile in session=" + session[:appjsonfile]

   if !session[:heroku_oauth_token]
   <<-HTML
   To deploy this app in your Heroku account, please first <a href='/auth/heroku'>Sign in with Heroku</a>
   HTML
   else
    # remove some elements this might be a new deployment
    
    
    puts "Using this app.json file:" + session[:appjsonfile]
    
    # read the specified app.json file
    jsonstr = ''
    File.open('public/apps/'+session[:appjsonfile], 'r') do |f|
      f.each_line do |line|
        jsonstr.concat(line)
      end
    end
    if(jsonstr=='')
      body "Invalid app configuration specified."
    end 

    # extract stuff from the app.json
    jsonparams = JSON.parse(jsonstr)
    processJson(jsonparams)
    if(session[:configvar_defaults])
      if(session[:configvar_defaults]["INSTALLED_BY"])
        session[:configvar_defaults]["INSTALLED_BY"] = "app-assembly" # see if there is a way to get this from the env
      end
    end
    
    # use the form template. give it the name and description of the app being deployed, the set of addons, 
    # the config vars with their defaults, the website specified in the app.json and the source url of the deployment
    haml :form, :locals => {:app => session[:name], 
                            :desc => session[:description], 
                            :adds => session[:addons], 
                            :vars => session[:configvar_defaults],
                            :website => session[:website],
                            :source_url => session[:source_url]
                            }  
   end
end

def printHash(hash)
  hash.each do |key, value|
    out = ''
    if (key)
      out = key + ":"
    end
    if(value)
      out = out + value
    else
      out = out + "''"
    end
    puts out  
  end
end

# helper method to extract stuff from the app.json
def processJson(input_json)
  session[:name] = input_json["name"] || "No name"
  session[:description] = input_json["description"] || ""
  
  configvar_defaults = Hash.new # this will hold the config var name and default value for now
  allvars = input_json["env"]
  if(allvars)
    allvars.each do | var, var_details |
      if(!var_details["generator"] || var_details["generator"]=="") # if something is going to be generated exclude it from the form
        configvar_defaults[var] = var_details["default"] || ""
      end
    end
  end
  session[:configvar_defaults] = configvar_defaults
  session[:addons] = input_json["addons"] 
  if(input_json["success_url"]) 
    session[:success_url] = input_json["success_url"]
  end
  if(input_json["website"]) 
    session[:website] = input_json["website"]
  end
end

# this is the target of the form submission
get "/deploy" do
  if !session[:heroku_oauth_token]
    redirect "/"
  end
  # clear out the data that is pertinent to each deployment
  session[:setupid] = nil
  session[:buildid] = nil
  sourceurl = session[:source_url]

  envStr = ''
  dochop = false # if we end up filling the envstr, we need to remove a trailing , because of how this loop below works
  params.each do |var_name, var_value|
    envStr = envStr + '"' + var_name + '":"' + var_value + '",'
    dochop = true
  end
  if(dochop) 
     envStr.chop!   # do the chop inplace
  end

  body = '{"source_blob": { "url":"'+ sourceurl+ '"}, "env": { ' + envStr + '} }'
  
  # make the call to the setup API
  res = Excon.post("https://nyata.herokuapp.com/app-setups",
                  :body => body,
                  :headers => { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}", "Content-Type" => "application/json"}
                 )
                 
  id = MultiJson.decode(res.body)["id"]
  
  #sometimes we get an unauthorized response if the oauth token expires
  if(id=="unauthorized")
    session[:heroku_oauth_token] = nil
    redirect "/"
  end
  
  # if no id was returned, there was a failure. or a failure may be indicated. in either case, show failure message to user
  if(id=="invalid_params" || id=="unauthorized" || id=="")
      message = MultiJson.decode(res.body)["message"]
      body message
  else
    # if it didn't fail, get the created app's name and then redirect to status
    session[:setupid] = id
    puts res.body
    session[:appname] = MultiJson.decode(res.body)["app"]["name"] || "No name"
    redirect "/status"
  end  
end

# the status page has 3 sections each of which are individually refreshed with other calls
get "/status" do
  # can't do much status without the setup id
  if !session[:setupid] 
      redirect "/deploy"
  end
 
  # render the status page template and give it the appname
  haml :status, :locals => {:appname => session[:appname]}
end

  # get the overall status fragment
get "/overall-status" do
  # poll the setup api for status
  statuscall = Excon.new("https://nyata.herokuapp.com",
      headers: { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}" })
  res = statuscall.get(path: "/app-setups/"+session[:setupid])
  newstatus = MultiJson.decode(res.body)["status"] 

  statusmsg = "Your application setup is "+newstatus
  if(newstatus == "failed")
    puts res.body
    statusmsg = "Your application setup has failed"# ["+MultiJson.decode(res.body["failure_message"])+"]"
  end
  if(newstatus == "succeeded")
    statusmsg = 'Your application setup succeeded. To try the app we just setup for you, <a href="http://' + session[:appname] + '.herokuapp.com' + session[:success_url]+ '">Click here</a>'
  end
  
  body statusmsg
end

# get the fragment for overall status
get "/setup-status" do
    # get the overall status
    statuscall = Excon.new("https://nyata.herokuapp.com",
                    headers: { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}" })
    res = statuscall.get(path: "/app-setups/"+session[:setupid])
    newstatus = MultiJson.decode(res.body)["status"] || "Not Available"
    
    statusOutput = res.body
    
    if(res.body)
      tempJson = JSON.parse(res.body)
      statusOutput = "<pre class='pre-scrollable'>"+JSON.pretty_generate(tempJson)+"</pre>"
    end
      
 
    overallstatus = "Setup status: " + newstatus + "<br><br>" + "Detailed status: <br>" + statusOutput + "<br><br>"
    body overallstatus
end

# get the fragment for build status
get "/build-status" do
    # use some defaults because builds take some time to be kicked off
    buildstatus = "Build not started"
    buildstatusdetails = "Not available"
    output = "Build status: " + buildstatus + "<br><br>" + "Detailed status: <br>" + buildstatusdetails + "<br><br>"
    if(!session[:buildid])
        # if you don't have the build id yet, poll the setup API to see if the build has been kicked off
        statuscall = Excon.new("https://nyata.herokuapp.com",
                                headers: { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}" })
        res = statuscall.get(path: "/app-setups/"+session[:setupid])
        # get the build id
        buildid = MultiJson.decode(res.body)["build"]["id"]
        session[:buildid] = buildid
        
    end
    if(session[:buildid])
        
        # if indeed we have the build id now, call the build API with the app name and build id
        buildcall = Excon.new("https://api.heroku.com",
                        headers: { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}",
                                   "Accept" => "application/vnd.heroku+json; version=3"  })
        buildcallpath = "/apps/" + session[:appname] + "/builds/" + session[:buildid] + "/result"
        puts "the build id is "+buildcallpath
        buildres = buildcall.get(path: buildcallpath)
        
        buildstatusdetails = buildres.body
        if(buildres.body)
            tempJson = JSON.parse(buildres.body)
            buildstatusdetails = "<pre class='pre-scrollable'>"+JSON.pretty_generate(tempJson)+"</pre>"
        end
        
        if(buildres.body)
          if(MultiJson.decode(buildres.body)["build"])
            buildstatus = MultiJson.decode(buildres.body)["build"]["status"]
          end
        end
        output = "Build status: " + buildstatus + "<br><br>" + "Detailed status: <br>" + buildstatusdetails + "<br><br>"
    end
    
    body output
end

# callback for heroku oauth
get "/auth/heroku/callback" do
  session[:heroku_oauth_token] =
    request.env["omniauth.auth"]["credentials"]["token"]
  redirect "/"
end

get "/logout" do
  session[:heroku_oauth_token] = nil
  body "You are now logged out"
end

get "/getting-started" do
  <<-HTML
    
  HTML
end