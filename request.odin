package bifrost

import "core:strings"
import "core:fmt"
import "core:testing"

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

    raw_url := fmt.tprintf("%s://%s%s%s%s", url.scheme, url.host, url.path, url.query, url.fragment)
    fmt.sbprintf(&sb, "%s %s HTTP/1.1\r\n", _request_method_str[method], raw_url)

    fmt.sbprintf(&sb, "Host: %s\r\n", raw_url)
    fmt.sbprint(&sb, "Connection: keep-alive\r\n")
    for h, _ in headers {
        fmt.sbprintf(&sb, "%s: %s\r\n", h.key, h.val)
    }

    strings.write_string(&sb, "\r\n")
    strings.write_bytes(&sb, body)
    return sb.buf[:]
}

@(test)
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

