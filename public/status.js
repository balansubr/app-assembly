$.ajaxSetup ({  
     cache: false  
  });
  
$(document).ready(function() { update_status(); });

function update_status() {
    $.get("/overall-status", 
          function(data) {
            $("#overallstatus").html(data);
            $("#setupdetails").load("/setup-details");
            $("#builddetails").load("/build-details");
            window.setTimeout(update_status, 5000);
          },
          'text');
}

Xhr.Options.spinner = 'spinner';