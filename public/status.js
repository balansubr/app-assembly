$.ajaxSetup ({  
     cache: false  
  });
  
$(document).ready(function() { update_status(); });

function update_status() {
    $.get("/overall-status", 
          function(data) {
            $("#overallstatus").load("/overall-status");
            $("#setupstatus").load("/setup-status");
            $("#buildstatus").load("/build-status");
            window.setTimeout(update_status, 10000);
          },
          'text');
}

Xhr.Options.spinner = 'spinner';