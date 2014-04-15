$.ajaxSetup ({  
     cache: false  
  });
  
$(document).ready(function() { update_status(); });

function update_status() {
    $.get("/overall-status", 
          function(data) {
            $("#overallstatus").html(data);
            $("#setupstatus").load("/setup-status");
            
            window.setTimeout(update_status, 10000);
          },
          'text');
}

Xhr.Options.spinner = 'spinner';