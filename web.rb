$stdout.sync = $stderr.sync = true

require "cgi"
require "excon"
require "multi_json"
require "sinatra"
require "omniauth"
require "omniauth-heroku"
require "base64"
require "haml"

use Rack::Session::Cookie, :secret => ENV["COOKIE_SECRET"]
use OmniAuth::Builder do
  provider :heroku, ENV["HEROKU_OAUTH_ID"], ENV["HEROKU_OAUTH_SECRET"], { scope: "global" }
end

get "/" do
   if !session[:heroku_oauth_token]
   <<-HTML
   To deploy this app in your Heroku account, please first <a href='/auth/heroku'>Sign in with Heroku</a>
   HTML
   else
     <<-HTML
     <p>Provide your deployment details below<br><br>
        <form name="input" action="/deploy" method="get">
          URL to source tarball: <input type="text" name="source_url" size="80" value="https://github.com/balansubr/SampleTimeApp/tarball/master/"><br>
          First name: <input type="text" name="firstname"><br>
          Last name: <input type="text" name="lastname"><br>
          <input type="submit" value="Submit">
        </form>
        </p>
   HTML
  end
end

get "/deploy" do
  firstname = params[:firstname] || "Not specified"
  lastname = params[:lastname] || "Not specified"
  sourceurl = params[:source_url] || "Not specified"
  installedby = "personalized-clock-factory"
  
  body = '{"source_blob": { "url":"'+ sourceurl+ '"}, "env": { "INSTALLED_BY":"'+ installedby+'", "LAST_NAME":"'+ lastname+'", "FIRST_NAME":"'+ firstname+'"} }'
  
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
  statuscall = Excon.new("https://nyata.herokuapp.com/app-setups",
      headers: { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}" })
  res = statuscall.get(path: "/"+session[:setupid])
  newstatus = MultiJson.decode(res.body)["status"] 
  id = MultiJson.decode(res.body)["id"]

  statusmsg = "Trying with "+session[:setupid]+" Getting "+res.body
  if(newstatus == "failed")
    statusmsg = "Failed ["+MultiJson.decode(res.body["failure_message"])+"]";
  end
  if(newstatus == "succeeded")
    statusmsg = "Link to your own clock: <a href=\"" + session[:appname] + ".herokuapp.com" + success_url + "\">Click here</a>"
  end
  
  body statusmsg
end

get "/setup-status" do
    # get the overall status
    statuscall = Excon.new("https://nyata.herokuapp.com/app-setups",
                    headers: { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}" })
    res = statuscall.get(path: "/"+session[:setupid])
    newstatus = MultiJson.decode(res.body)["status"] || "Not Available"
 
    overallstatus = "Setup status: " + newstatus + "<br><br>" + "Detailed status: <br>" + MultiJson.dump(res.body, :pretty => true) + "<br><br>"
    body overallstatus
end

get "/build-status" do
    # get the build status
    if(!session[:buildid])
        # get the overall status
        statuscall = Excon.new("https://nyata.herokuapp.com/app-setups",
                                headers: { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}" })
        res = statuscall.get(path: "/"+session[:setupid])
        buildid = MultiJson.decode(res.body)["build"]["id"] || "none"
    end
    buildstatus = "None yet"
    if(buildid!="none")
        session[:buildid] = buildid
        buildcall = Excon.new("https://api.heroku.com/",
                        headers: { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}" })
        buildcallpath = "/apps/" + appname + "/builds/" + buildid + "/result"
        buildres = statuscall.get(path: buildcallpath )
        buildstatus = buildres.body
    end
    
    body buildstatus
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