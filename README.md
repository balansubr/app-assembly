app-assembly
============

A simple web app for stamping out app.json apps on Heroku

What does it do
===============
app-assembly provides a simple web interface for deploying app.json enabled apps. It,
- serves as a directory of app.json's used by various apps
- parses app.jsons
- performs the OAuth dance with Heroku to deploy on behalf of a user
- dynamically creates forms to collect configuration variable values from end users
- shows the enduser what add ons will be provisioned
- displays ongoing status of the deployment and associated build
- provides a link to the provisioned app

See it in action at [https://app-assembly.herokuapp.com](https://app-assembly.herokuapp.com)

How to use it
=============
By default, app-assembly is hard coded to deploy the SampleTimeApp whose app.json is present as clock_app.json in the ```public/apps``` folder. If you hit the default url with no parameters, app-assembly deploys an instance of this sample app in your heroku account. You can ask app-assembly to deploy a different app by providing it the source url and the specific app.json associated with that app that is already on the server under ```public/apps```. 

For example, the above default is actually:

```
https://app-assembly.herokuapp.com/?src=https%3A%2F%2Fgithub.com%2Fbalansubr%2FSampleTimeApp%2Ftarball%2Fmaster%2F&json=clock_app.json 
```

The source url must resolve to a tarball. While it makes more sense to simply provide the source url and parse out the app.json from the tarball, its more work for app-assembly to do and app-assembly is simply a demo app at this time.

To add new apps to app-assembly, simply add the app.json for that app to this folder with a unique name prefix. You may also fork this repo to add your own app.jsons.

After you complete the OAuth dance, app-assembly lets you fill in your own values for configuration variables specified in the app.json for that app. It also shows the default values, if any, specified in the app.json. At this time, it does not perform any validation (e.g. for variables marked as required in app.json). 

Once you submit the form, app-assembly calls the Heroku setup API to kick off the provisioning of the app. The status page refreshes every 5 seconds and at this time basically dumps the response without any pretty formatting. app-assembly also extracts the app name and build id and calls the Heroku build API to get details of the build status. However at this time, if the app provisioning fails, there is no way to get the build status because the API implementation destroys the provisioned app if there is any failure.

Once the deployment completes successfully, app-assembly uses the details of the provisioned app and the success_url specified in the app's app.json to point you to the provisioned app.


