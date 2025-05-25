package bifrost

import "core:strings"
import "core:fmt"
import "core:net"
import "core:testing"
import "core:log"

HttpHeader :: struct {
    key: string,
    val: string,
}

Request_Method :: enum i8 {
    Get, Post,
}

@(private)
_request_method_str := [Request_Method]string{
    .Get = "GET", .Post = "POST",
}

/*
Builds an HTTP request string

Inputs:
- method: An enumerated value from `Request_Method`
- url: An initialized `HttpUrl` struct
- headers: An optional slice of `HttpHeader` structs
- body: The bytes for the request body

Returns:
- res: A slice of bytes representing an HTTP request
*/
@(private)
_build_http_request :: proc(method: Request_Method, url: HttpUrl, headers: []HttpHeader, body: []u8) -> (res: []u8) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    raw_url := fmt.tprintf("%s%s%s", url.path, url.query, url.fragment)
    fmt.sbprintf(&sb, "%s %s HTTP/1.1\r\n", _request_method_str[method], raw_url)

    fmt.sbprintf(&sb, "Host: %s\r\n", url.host)
    fmt.sbprint(&sb, "Connection: keep-alive\n")
    for h, _ in headers {
        fmt.sbprintf(&sb, "%s: %s\r\n", h.key, h.val)
    }

    strings.write_string(&sb, "\r\n")
    strings.write_bytes(&sb, body)
    return sb.buf[:]
}

just_a_test :: proc() {
    host_or_endpoint, host_err := net.parse_hostname_or_endpoint("dummyjson.com")
    log.infof("host_err: %v\n", host_err)

    endpoint: net.Endpoint
    switch t in host_or_endpoint {
    case net.Endpoint:
        endpoint = t
    case net.Host:
        ep4, ep6, _ := net.resolve(t.hostname)
        endpoint = ep4 if ep4.address != nil else ep6

        endpoint.port = t.port
        if endpoint.port == 0 {
            endpoint.port = "http" == "https" ? 443 : 80
        }
    case:
        unreachable()
    }

    log.infof("endpoint: %v\n", endpoint)

    socket, dial_err := net.dial_tcp(endpoint)
    defer net.close(socket)
    log.infof("dial_err: %v\n", dial_err)

    request := "GET /test HTTP/1.1\r\nHost: dummyjson.com\r\nConnection: close\r\n\r\n"
    //request := _build_http_request(.Get, {"https", "jsonplaceholder.typicode.com", "/todos/1", "", ""}, {}, {})
    log.infof("request: \n%s\n", request)

    res := new(HttpResponse)
    defer free(res)
    res_err: Parse_Error

    buf := make([]u8, 1024)
    defer delete(buf)

    for {
        if res.body != nil {
            break
        }

        _, send_err := net.send_tcp(socket, transmute([]u8)request)
        log.infof("send_err: %v\n", send_err)

        _, recv_err := net.recv_tcp(socket, buf)
        log.infof("recv_err: %v\n", recv_err)

        res, res_err = _parse_http_response(buf)
        log.infof("res_err: %v\n", res_err)
    }
    log.infof("res: %v\n", res)
    log.infof("body: %s\n", res.body)
}

@(test)
test_perform_http_request :: proc(t: ^testing.T) {
    just_a_test()
}

/*@(test)
test_build_http_request :: proc(t: ^testing.T) {
    tests := []struct{method: Request_Method, url: HttpUrl, headers: []HttpHeader, body, res: string}{
        {
            .Get, HttpUrl{"http", "foo.com", "/", "", ""}, nil, "",
            "GET http://foo.com/ HTTP/1.1\r\n" +
            "Host: http://foo.com/\r\n" +
            "Connection: keep-alive\r\n\r\n",
        },
        {
            .Get, HttpUrl{"http", "foo.com", "/bar", "", ""}, nil, "",
            "GET http://foo.com/bar HTTP/1.1\r\n" +
            "Host: http://foo.com/bar\r\n" +
            "Connection: keep-alive\r\n\r\n",
        },
        {
            .Get, HttpUrl{"http", "foo.com", "/bar", "?foo=bar", ""}, nil, "",
            "GET http://foo.com/bar?foo=bar HTTP/1.1\r\n" +
            "Host: http://foo.com/bar?foo=bar\r\n" +
            "Connection: keep-alive\r\n\r\n",
        },
        {
            .Get, HttpUrl{"http", "foo.com", "/bar", "#foo", ""}, nil, "",
            "GET http://foo.com/bar#foo HTTP/1.1\r\n" +
            "Host: http://foo.com/bar#foo\r\n" +
            "Connection: keep-alive\r\n\r\n",
        },
        {
            .Get, HttpUrl{"http", "foo.com", "/bar", "?foo=bar", "#foo"}, nil, "",
            "GET http://foo.com/bar?foo=bar#foo HTTP/1.1\r\n" +
            "Host: http://foo.com/bar?foo=bar#foo\r\n" +
            "Connection: keep-alive\r\n\r\n",
        },
        {
            .Post, HttpUrl{"http", "foo.com", "/", "", ""}, nil, `{"foo": "bar"}`,
            "POST http://foo.com/ HTTP/1.1\r\n" +
            "Host: http://foo.com/\r\n" +
            "Connection: keep-alive\r\n\r\n" +
            `{"foo": "bar"}`,
        },
        {
            .Get, HttpUrl{"http", "foo.com", "/", "", ""}, []HttpHeader{{"Authorization", "123"}}, "",
            "GET http://foo.com/ HTTP/1.1\r\n" +
            "Host: http://foo.com/\r\n" +
            "Connection: keep-alive\r\n" +
            "Authorization: 123\r\n\r\n",
        },
        {
            .Post, HttpUrl{"http", "foo.com", "/", "", ""}, []HttpHeader{{"Authorization", "123"}}, `{"foo": "bar"}`,
            "POST http://foo.com/ HTTP/1.1\r\n" +
            "Host: http://foo.com/\r\n" +
            "Connection: keep-alive\r\n" +
            "Authorization: 123\r\n\r\n" +
            `{"foo": "bar"}`,
        },
    }
    for test, _ in tests {
        request := _build_http_request(test.method, test.url, test.headers, transmute([]u8)test.body)
        testing.expect_value(t, string(request), test.res)
    }
}
*/
