package bifrost

import "core:fmt"
import "core:testing"
import "core:log"
import "core:strings"

HttpRequest :: struct {
    url:        HttpUrl,
    headers:    map[string]string,
    method:     string,
    raw_url:    string,
    body:       []u8,
}

Request_Method :: enum i32 {
    Get,
    Post,
}

@(private)
_request_method_strings := [Request_Method]string{
    .Get    = "GET",
    .Post   = "POST",
}

build_http_request_v2 :: proc(method: Request_Method, url: HttpUrl, body: []u8) -> (res: ^HttpRequest) {
    raw_url := fmt.aprintf("%s://%s%s%s%s", url.scheme, url.host, url.path, url.query, url.fragment)
    defer delete(raw_url)

    headers := map[string]string{}
    headers["Host"] = raw_url
    headers["Connection"] = "keep-alive"
    defer delete(headers)

    res = new(HttpRequest)
    res.url = url
    res.headers = headers
    res.method = _request_method_strings[method]
    res.raw_url = raw_url
    res.body = body
    return res
}

@(test)
test_build_http_request :: proc(t: ^testing.T) {
    request := build_http_request_v2(.Get, {"http", "foo.com", "/", "", ""}, []u8{})
    defer free(request)
    log.infof("request: %v\n", request)
}
