$stdout.sync = $stderr.sync = true

require "cgi"
require "excon"
require "multi_json"
require "sinatra"
require "omniauth"
require "omniauth-heroku"

use Rack::Session::Cookie, :secret => ENV["COOKIE_SECRET"]
use OmniAuth::Builder do
  provider :heroku, ENV["HEROKU_OAUTH_ID"], ENV["HEROKU_OAUTH_SECRET"], { scope: "identity" }
end

username = "BooBoo"

get "/" do
   if !session[:heroku_oauth_token]
   <<-HTML
   To deploy this app in your Heroku account, please first <a href='/auth/heroku'>Sign in with Heroku</a>
   HTML
   else
     <<-HTML
     <p>Provide your deployment details below<br><br>
        <form name="input" action="/deploy" method="get">
          URL to source tarball: <input type="text" name="source_url" length="60" value="https://github.com/balansubr/heroku-oauth-example-ruby/tarball/master/"><br>
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
  
  res = Excon.post('https://nyata.herokuapp.com/app-setups',
                  :body => '{ "source_blob": { "url": #{sourceurl} }, "env": { "INSTALLED_BY": #{installedby}, "LAST_NAME": #{lastname}, "FIRST_NAME": #{firstname} } }',
                  :headers => { "Authorization" => "Bearer #{session[:heroku_oauth_token]}", "Content-Type" => "application/json"}
                 )
                 
  message = MultiJson.decode(res.body)["message"] || MultiJson.decode(res.body)["status"]
           
  <<-HTML
      #{CGI.escapeHTML(message)}
    HTML
 
end


get "/auth/heroku/callback" do
  session[:heroku_oauth_token] =
    request.env["omniauth.auth"]["credentials"]["token"]
#  api = Excon.new(ENV["HEROKU_API_URL"] || "https://api.heroku.com",
#      headers: { "Authorization" => "Bearer #{session[:heroku_oauth_token]}" },
#      ssl_verify_peer: ENV["SSL_VERIFY_PEER"] != "false")
#  res = api.get(path: "/account", expects: 200)
#  username = MultiJson.decode(res.body)["name"]
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
