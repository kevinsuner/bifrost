package bifrost

import "core:testing"
import "core:log"
import "core:fmt"

/*
TODO:
- Parse HTTP url into an HttpUrl struct                                 ✓
- Create a proc to initialize an HttpRequest struct                     ×
    - Takes HttpUrl, Headers (map[string]string), Body ([]u8)           ×
- Parse HTTP response headers and body into an HttpResponse struct      ×
- Create a proc to perform a dynamically allocated HTTP GET request     ×
*/

HttpUrl :: struct {
    scheme:     string,
    host:       string,
    path:       string,
    query:      string,
    fragment:   string,
}

HttpRequest :: struct {
    url:        HttpUrl,
    headers:    map[string]string,
    method:     string,
    body:       []u8,
}

Request_Method :: enum i32 {
    Get,
    Post,
    Put,
    Patch,
    Delete,
}

build_http_request :: proc(method: string, url: HttpUrl, body: []u8) -> (res: HttpRequest) {
    headers := make(map[string]string)
    headers["Host"] = fmt.aprintf("%s://%s%s%s%s", url.scheme, url.host, url.path, url.query, url.fragment)
    headers["Connection"] = "keep-alive"
    return HttpRequest{url, headers, method, body}
}

@(test)
test_build_http_request :: proc(t: ^testing.T) {
    request := build_http_request("GET", HttpUrl{"http", "foo.com", "/", "", ""}, []u8{})
    log.infof("request: %v\n", request)
}

@(test)
test_size_of_things :: proc(t: ^testing.T) {
    http_url: HttpUrl
    log.infof("size_of(HttpUrl): %d\n", size_of(http_url)) 
    headers: map[string]string
    log.infof("size_of(map[string]string): %d\n", size_of(headers))
    body: []u8
    log.infof("size_of([]u8): %d\n", size_of(body))
    method: string
    log.infof("size_of(string): %d\n", size_of(method))
    http_req: HttpRequest
    log.infof("size_of(HttpRequest): %d\n", size_of(http_req))
}
