package bifrost

import "core:fmt"
import "core:strings"
import "core:testing"
import "core:log"

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
    raw_url := fmt.aprintf("%s://%s%s%s%s", url.scheme, url.host, url.path, url.query, url.fragment)
    defer delete(raw_url)

    headers := map[string]string{}
    headers["Host"] = raw_url
    headers["Connection"] = "keep-alive"
    defer delete(headers)

    res = new(HttpRequest)
    res.url = url
    res.headers = headers
    res.method = _request_method_to_string[method] 
    res.raw_url = raw_url
    res.body = body
    return res
}

http_request_to_bytes :: proc(request: ^HttpRequest) -> (res: []u8) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    request_line := strings.concatenate({request.method, " ", request.raw_url, " ", "HTTP/1.1\r\n"})
    defer delete(request_line)
    strings.write_string(&sb, request_line)

    for k, v in request.headers {
        header := fmt.aprintf("%s: %s\r\n", k, v)
        defer delete(header)
        strings.write_string(&sb, header)
    }

    strings.write_string(&sb, "\r\n")
    strings.write_bytes(&sb, request.body)
    return sb.buf[:]
}

@(test)
test_build_request_and_to_bytes :: proc(t: ^testing.T) {
    url, _ := parse_http_url("http://foo.com/")
    req := build_http_request(.Get, url, []u8{})
    defer free(req)
    req_bytes := http_request_to_bytes(req)
    log.infof("req: \n%s\n", req_bytes)
}

