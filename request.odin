package bifrost

import "core:fmt"
import "core:strings"

HttpRequest :: struct {
    url:        HttpUrl,
    headers:    map[string]string,
    method:     string,
    body:       []u8,
}

Request_Method :: enum i8 {
    Get,
    Post,
}

@(private)
_request_method_to_str := [Request_Method]string{
    .Get    = "GET",
    .Post   = "POST",
}

/*
Initializes a `HttpRequest` with specified method `Request_Method`, url `HttpUrl` and body `[]u8`

Inputs:
- method: An enumerated value from `Request_Method`
- url: An initialized `HttpUrl` struct
- body: The bytes for the request body

Returns:
- res: A pointer to an initialized `HttpRequest` struct

Example:

    import "core:fmt"
    import "libs/bifrost"

    main :: proc() {
        url, _ := bifrost.parse_http_url("http://foo.com/")
        request := bifrost.build_http_request(.Get, url, nil)
        defer free(request)
        fmt.printf("%v\n", request)
    }

Output:

    &HttpRequest{HttpUrl{"http", "foo.com", "/", "", ""}, map[Host="http://foo.com/", Connection="keep-alive"], "GET", []}

*/
build_http_request :: proc(method: Request_Method, url: HttpUrl, body: []u8) -> (res: ^HttpRequest) {
    headers := map[string]string{}
    headers["Host"] = fmt.tprintf("%s://%s%s%s%s", url.scheme, url.host, url.path, url.query, url.fragment)
    headers["Connection"] = "keep-alive"
    defer delete(headers)

    res = new(HttpRequest)
    res.url = url
    res.headers = headers
    res.method = _request_method_to_str[method]
    res.body = body
    return res
}

/*
Forms an HTTP request string using an `HttpRequest` struct

Inputs:
- request: A pointer to an initialized `HttpRequest` struct

Returns:
- res: A slice of bytes representing an HTTP request

Example

    import "core:fmt"
    import "libs/bifrost"

    main :: proc() {
        url, _ := bifrost.parse_http_url("http://foo.com/")
        request := bifrost.build_http_request(.Get, url, nil)
        defer free(request)
        fmt.printf("\n%s\n", bifrost.http_request_to_bytes(request))
    }

Output:

    GET http://foo.com/ HTTP/1.1
    Connection: keep-alive
    Host: http://foo.com/

*/
http_request_to_bytes :: proc(request: ^HttpRequest) -> (res: []u8) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    fmt.sbprintf(&sb, "%s %s HTTP/1.1\r\n", request.method, request.headers["Host"])
    for k, v in request.headers {
        fmt.sbprintf(&sb, "%s: %s\r\n", k, v)
    }
    strings.write_string(&sb, "\r\n")
    strings.write_bytes(&sb, request.body)
    return sb.buf[:]
}

