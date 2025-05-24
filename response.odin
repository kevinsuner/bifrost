package bifrost

import "core:strings"
import "core:testing"
import "core:log"

HttpResponse :: struct {
    status:     string,
    headers:    []HttpHeader,
    body:       []u8,
}

/*
Parses `buf` into an `^HttpResponse` struct

Inputs:
- buf: The input bytes

Returns:
- res: A pointer to an initialized `^HttpResponse` struct
- err: An enumerated value from `Parse_Error`
*/
@(private)
_parse_http_response :: proc(buf: []u8) -> (res: ^HttpResponse, err: Parse_Error) {
    str := string(buf)
    status: string
    headers: [dynamic]HttpHeader
    defer delete(headers)
    body: [dynamic]u8
    defer delete(body)
    found_blank_line: bool

    for line in strings.split_lines_iterator(&str) {
        if line == "" {
            // used as delimiter between headers and body
            found_blank_line = true
            continue
        }

        if status == "" {
            if !strings.contains(line, "HTTP") {
                // status line must contain HTTP
                return nil, .Status_Line_Not_Found
            }

            arr := strings.split(line, " ")
            defer delete(arr)
            if len(arr) < 3 {
                // status line must follow this format
                // [HTTP-version] [status-code] [reason-phrase]
                return nil, .Invalid_Status_Line
            }
            status = arr[1]
        } else {
            if found_blank_line {
                append(&body, ..transmute([]u8)line)
                continue
            }

            arr := strings.split_n(line, ":", 2)
            defer delete(arr)
            if len(arr) < 2 || len(arr[0]) == 0 {
                // headers must follow this format
                // [key] : [val]
                return nil, .Invalid_Header
            }
            append(&headers, HttpHeader{arr[0], strings.trim(arr[1], " ")})
        }
    }

    res = new(HttpResponse)
    res.status = status
    res.headers = headers[:]
    res.body = body[:]
    return res, .None
}

@(test)
test_parse_http_response :: proc(t: ^testing.T) {
    body : string : `{"foo": "bar"}`
    tests := []struct{buf: string, res: ^HttpResponse, err: Parse_Error}{
        {
            "HTTP/1.1 200 OK\r\nHost: http://foo.com/\r\nConnection: keep-alive\r\n\r\n" + body,
            &{"200", []HttpHeader{{"Host", "http://foo.com/"},{"Connection", "keep-alive"}}, transmute([]u8)body},
            .None,
        },
        {
            "HTTP/1.1 200 OK\r\nHost: http://foo.com/\r\nConnection: keep-alive\r\n\r\n",
            &{"200", []HttpHeader{{"Host", "http://foo.com/"},{"Connection", "keep-alive"}}, []u8{}},
            .None,
        },
        {
            "HTTP/1.1 200 OK\r\nHost: http://foo.com/\r\nConnection:\r\n\r\n",
            &{"200", []HttpHeader{{"Host", "http://foo.com/"},{"Connection", ""}}, []u8{}},
            .None,
        },
        {"HTTP/1.1 200 OK\r\n", &{"200", []HttpHeader{}, []u8{}}, .None},
        {"Host: http://foo.com/\r\nConnection: keep-alive\r\n\r\n", nil, .Status_Line_Not_Found},
        {"HTTP/1.1 OK\r\nHost: http://foo.com/\r\nConnection: keep-alive\r\n\r\n", nil, .Invalid_Status_Line},
        {"HTTP/1.1 200 OK\r\nHost: http://foo.com/\r\n: http://foo.com/\r\n\r\n", nil, .Invalid_Header},
        {"HTTP/1.1 200 OK\r\nHost: http://foo.com/\r\n:\r\n\r\n", nil, .Invalid_Header},
    }
    for test, _ in tests {
        res, err := _parse_http_response(transmute([]u8)test.buf)
        if res != nil {
            testing.expect_value(t, res.status, test.res.status)
            for h, i in res.headers {
                testing.expect_value(t, h.key, test.res.headers[i].key)
                testing.expect_value(t, h.val, test.res.headers[i].val)
            }
            testing.expect_value(t, string(res.body), string(test.res.body))
            free(res)
        } else {
            testing.expect_value(t, res, test.res)
        }
        testing.expect_value(t, err, test.err)
    }
}
