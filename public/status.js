$.ajaxSetup ({  
     cache: false  
  });
  
$(document).ready(function() { update_status(); });

function update_status() {
    $.get("/overall-status", 
          function(data) {
            $("#overallstatus").html(data);
            $("#setupstatus").load("/setup-status");
            $("#buildstatus").load("/build-status");
            window.setTimeout(update_status, 5000);
          },
          'text');
}
