package bifrost

import "core:fmt"
import "core:strings"

HttpRequest :: struct {
    url:        HttpUrl,
    headers:    map[string]string,
    method:     string,
    raw_url:    string,
    body:       []u8,
}

Request_Method :: enum i8 {
    Get,
    Post,
}

@(private)
_request_method_to_string := [Request_Method]string{
    .Get    = "GET",
    .Post   = "POST",
}

build_http_request :: proc(method: Request_Method, url: HttpUrl, body: []u8) -> (res: ^HttpRequest) {
    headers := map[string]string{}
    headers["Host"] = fmt.tprintf("%s://%s%s%s%s", url.scheme, url.host, url.path, url.query, url.fragment)
    headers["Connection"] = "keep-alive"
    defer delete(headers)

    res = new(HttpRequest) 
    res.url = url
    res.headers = headers
    res.method = _request_method_to_string[method]
    res.raw_url = res.headers["Host"]
    res.body = body
    return res
}

http_request_to_bytes :: proc(request: ^HttpRequest) -> (res: []u8) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    fmt.sbprintf(&sb, "%s %s HTTP/1.1\r\n", request.method, request.raw_url)
    for k, v in request.headers {
        fmt.sbprintf(&sb, "%s: %s\r\n", k, v)
    }

    strings.write_string(&sb, "\r\n")
    strings.write_bytes(&sb, request.body)
    return sb.buf[:]
}

