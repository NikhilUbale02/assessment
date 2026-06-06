vcl 4.1;
backend default {
    .host = "nginx";
    .port = "8080";
}
sub vcl_recv {
    return(pass);
}
