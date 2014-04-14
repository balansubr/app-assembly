$stdout.sync = $stderr.sync = true

require "cgi"
require "excon"
require "multi_json"
require "sinatra"
require "omniauth"
require "omniauth-heroku"
require "base64"

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
  
  res = Excon.post('https://nyata.herokuapp.com/app-setups',
                  :body => body,
                  :headers => { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}", "Content-Type" => "application/json"}
                 )
                 
  # "Authorization" => "Bearer #{session[:heroku_oauth_token]}"
  # "Authorization" => "Basic OjIzZjFjYzY0LWRmMjItNDM2OS05OWMxLTExYjNkYmYyZWVjNg=="
  
  message = MultiJson.decode(res.body)["message"] || MultiJson.decode(res.body)["status"]
  
  if message == "pending"
     session[:setupid] = MultiJson.decode(res.body)["id"] || ""
     session[:buildid] = MultiJson.decode(res.body)["build"]["id"] || ""
     redirect "/status"
  end  
  <<-HTML
      #{CGI.escapeHTML(sourceurl)}
      {CGI.escapeHTML(message)}
    HTML
end

get "/status" do
  statuscall = Excon.new("https://nyata.herokuapp.com",
      headers: { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}" })
  res = statuscall.get(path: "/app-setups/"+session[:setupid])
  newstatus = MultiJson.decode(res.body)["status"]
  appname = MultiJson.decode(res.body)["app"]["name"]
  buildid = MultiJson.decode(res.body)["build"]["id"] || "none"
  
  buildstats = "None yet"
  
  if(buildid!="none")
    buildcall = Excon.new("https://api.heroku.com/",
                        headers: { "Authorization" => "Basic #{Base64.strict_encode64(":#{session[:heroku_oauth_token]}")}" })
    buildcallpath = "/apps/" + appname + "/builds/" + buildid + "/result"
    buildres = statuscall.get(path: buildcallpath )
    buildstatus = buildres.body || "None yet"
  end
  
  output = "Overall status:" + newstatus + "<br>" + "Detailed status: <br> " + res.body + "<br>"  + "Build status: <br>" + buildstatus + "<br>" + "<h2>Please refresh page for status updates</h2>"
  body output
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
