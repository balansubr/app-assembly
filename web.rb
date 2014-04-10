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

get "/" do
  if !session[:heroku_oauth_token]
    <<-HTML
    To deploy this app in your Heroku account please, <a href='/auth/heroku'>Sign in with Heroku</a>
    HTML
  else
    <<-HTML
    Hello #{CGI.escapeHTML(user_name)}, Provide your deployment details below
    <form name="input" action="/deploy" method="get">
      URL to source tarball: <input type="text" name="source_url"><br>
      Last name: <input type="text" name="lastname">
      <input type="submit" value="Submit">
    </form>
  HTML
end

get "/deploy" do
  <<-HTML
  I am going to deploy now!
  HTML
end


get "/auth/heroku/callback" do
  session[:heroku_oauth_token] =
    request.env["omniauth.auth"]["credentials"]["token"]
  api = Excon.new(ENV["HEROKU_API_URL"] || "https://api.heroku.com",
      headers: { "Authorization" => "Bearer #{session[:heroku_oauth_token]}" },
      ssl_verify_peer: ENV["SSL_VERIFY_PEER"] != "false")
    res = api.get(path: "/account", expects: 200)
    user_name = MultiJson.decode(res.body)["name"]
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
