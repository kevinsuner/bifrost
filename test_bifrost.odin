#+feature dynamic-literals
package bifrost

import "core:testing"
import "core:mem"
import "core:log"

@(test)
test_has_control_character :: proc(t: ^testing.T) {
    tests := []struct{str: string, err: Url_Error}{
        {
            "https://foo.com/bar?foo=bar#foo",
            .None,
        },
        {
            "https://foo.com/bar?foo=bar#foo\n",
            .Found_Control_Character,
        },
        {
            "https://foo.com/bar?foo=bar#foo\r",
            .Found_Control_Character,
        },
        {
            "https://foo.com/bar?foo=bar#foo\x7f",
            .Found_Control_Character,
        },
    }
    for test, _ in tests {
        testing.expect_value(t, _has_control_character(test.str), test.err)
    }
}

@(test)
test_extract_scheme :: proc(t: ^testing.T) {
    tests := []struct{str, res, rest: string, err: Url_Error}{
        {
            "http://foo.com/bar?foo=bar#foo",
            "http",
            "//foo.com/bar?foo=bar#foo",
            .None,
        },
        {
            "https://foo.com/bar?foo=bar#foo",
            "https",
            "//foo.com/bar?foo=bar#foo",
            .None,
        },
        {
            "0https://foo.com/bar?foo=bar#foo",
            "",
            "0https://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            "+https://foo.com/bar?foo=bar#foo",
            "",
            "+https://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            "-https://foo.com/bar?foo=bar#foo",
            "",
            "-https://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            ".https://foo.com/bar?foo=bar#foo",
            "",
            ".https://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            "://foo.com/bar?foo=bar#foo",
            "",
            "://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            " https://foo.com/bar?foo=bar#foo",
            "",
            " https://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            "h ttps://foo.com/bar?foo=bar#foo",
            "",
            "h ttps://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            "h_ttps://foo.com/bar?foo=bar#foo",
            "",
            "h_ttps://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
    }
    for test, _ in tests {
        res, rest, err := _extract_scheme(test.str)
        testing.expect_value(t, res, test.res)
        testing.expect_value(t, rest, test.rest)
        testing.expect_value(t, err, test.err)
    }
}

@(test)
test_extract_host :: proc(t: ^testing.T) {
    tests := []struct{str, res, rest: string, err: Url_Error}{
        {
            "//foo.com/bar?foo=bar#foo",
            "foo.com",
            "/bar?foo=bar#foo",
            .None,
        },
        {
            "//foo.bar.com/bar?foo=bar#foo",
            "foo.bar.com",
            "/bar?foo=bar#foo",
            .None,
        },
        {
            "//.foo.com/bar?foo=bar#foo",
            "",
            "//.foo.com/bar?foo=bar#foo",
            .Host_Not_Found,
        },
        {
            "//foo.com./bar?foo=bar#foo",
            "",
            "//foo.com./bar?foo=bar#foo",
            .Host_Not_Found,
        },
        {
            "//-foo.com/bar?foo=bar#foo",
            "",
            "//-foo.com/bar?foo=bar#foo",
            .Host_Not_Found,
        },
        {
            "//foo.com-/bar?foo=bar#foo",
            "",
            "//foo.com-/bar?foo=bar#foo",
            .Host_Not_Found,
        },
        {
            "//foo/bar?foo=bar#foo",
            "",
            "//foo/bar?foo=bar#foo",
            .Host_Not_Found,
        },
        {
            "//f oo.com/bar?foo=bar#foo",
            "",
            "//f oo.com/bar?foo=bar#foo",
            .Host_Not_Found,
        },
        {
            "//f_oo.com/bar?foo=bar#foo",
            "",
            "//f_oo.com/bar?foo=bar#foo",
            .Host_Not_Found,
        },
    }
    for test, _ in tests {
        res, rest, err := _extract_host(test.str)
        testing.expect_value(t, res, test.res)
        testing.expect_value(t, rest, test.rest)
        testing.expect_value(t, err, test.err)
    }
}

@(test)
test_percent_encode_str :: proc(t: ^testing.T) {
    tests := []struct{str, res: string, err: mem.Allocator_Error}{
        {
            "/bar?foo=bar #foo",
            "/bar?foo=bar%20#foo",
            .None,
        },
        {
            "/bar?foo=bar;#foo",
            "/bar?foo=bar%3B#foo",
            .None,
        },
        {
            "/bar?foo=bar:#foo",
            "/bar?foo=bar%3A#foo",
            .None,
        },
        {
            "/bar?foo=bar[#foo",
            "/bar?foo=bar%5B#foo",
            .None,
        },
        {
            "/bar?foo=bar]#foo",
            "/bar?foo=bar%5D#foo",
            .None,
        },
        {
            "/bar?foo=bar{#foo",
            "/bar?foo=bar%7B#foo",
            .None,
        },
        {
            "/bar?foo=bar}#foo",
            "/bar?foo=bar%7D#foo",
            .None,
        },
        {
            "/bar?foo=bar<#foo",
            "/bar?foo=bar%3C#foo",
            .None,
        },
        {
            "/bar?foo=bar>#foo",
            "/bar?foo=bar%3E#foo",
            .None,
        },
        {
            "/bar?foo=bar\\#foo",
            "/bar?foo=bar%5C#foo",
            .None,
        },
        {
            "/bar?foo=bar^#foo",
            "/bar?foo=bar%5E#foo",
            .None,
        },
        {
            "/bar?foo=bar`#foo",
            "/bar?foo=bar%60#foo",
            .None,
        },
        {
            `/bar?foo=bar"#foo`,
            "/bar?foo=bar%22#foo",
            .None,
        },
    }
    for test, _ in tests {
        res, err := _percent_encode_str(test.str)
        testing.expect_value(t, res, test.res)
        testing.expect_value(t, err, test.err)
    }
}

@(test)
test_url_parse :: proc(t: ^testing.T) {
    tests := []struct{url: ^Url, raw_url: string, err: Client_Error}{
        {
            &{"http", "foo.com", "/bar", "?foo=bar&bar=foo", "#foo", "http://foo.com/bar?foo=bar&bar=foo#foo", 80},
            "http://foo.com/bar?foo=bar&bar=foo#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar&bar=foo", "#foo", "https://foo.com/bar?foo=bar&bar=foo#foo", 443},
            "https://foo.com/bar?foo=bar&bar=foo#foo",
            nil,
        },
        {
            &{"https", "foo.bar.com", "/bar", "?foo=bar", "#foo", "https://foo.bar.com/bar?foo=bar#foo", 443},
            "https://foo.bar.com/bar?foo=bar#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar", "#foo", "https://foo.com/bar?foo=bar#foo", 443},
            "https://foo.com/bar?foo=bar#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar%20", "#foo", "https://foo.com/bar?foo=bar #foo", 443},
            "https://foo.com/bar?foo=bar #foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar%3B", "#foo", "https://foo.com/bar?foo=bar;#foo", 443},
            "https://foo.com/bar?foo=bar;#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar%3A", "#foo", "https://foo.com/bar?foo=bar:#foo", 443},
            "https://foo.com/bar?foo=bar:#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar%5B", "#foo", "https://foo.com/bar?foo=bar[#foo", 443},
            "https://foo.com/bar?foo=bar[#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar%5D", "#foo", "https://foo.com/bar?foo=bar]#foo", 443},
            "https://foo.com/bar?foo=bar]#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar%7B", "#foo", "https://foo.com/bar?foo=bar{#foo", 443},
            "https://foo.com/bar?foo=bar{#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar%7D", "#foo", "https://foo.com/bar?foo=bar}#foo", 443},
            "https://foo.com/bar?foo=bar}#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar%3C", "#foo", "https://foo.com/bar?foo=bar<#foo", 443},
            "https://foo.com/bar?foo=bar<#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar%3E", "#foo", "https://foo.com/bar?foo=bar>#foo", 443},
            "https://foo.com/bar?foo=bar>#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar%5C", "#foo", "https://foo.com/bar?foo=bar\\#foo", 443 },
            "https://foo.com/bar?foo=bar\\#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar%5E", "#foo", "https://foo.com/bar?foo=bar^#foo", 443},
            "https://foo.com/bar?foo=bar^#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar%60", "#foo", "https://foo.com/bar?foo=bar`#foo", 443},
            "https://foo.com/bar?foo=bar`#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar%22", "#foo", `https://foo.com/bar?foo=bar"#foo`, 443},
            `https://foo.com/bar?foo=bar"#foo`,
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "?foo=bar", "", "https://foo.com/bar?foo=bar", 443},
            "https://foo.com/bar?foo=bar",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "", "#foo", "https://foo.com/bar#foo", 443},
            "https://foo.com/bar#foo",
            nil,
        },
        {
            &{"https", "foo.com", "/bar", "", "", "https://foo.com/bar", 443},
            "https://foo.com/bar",
            nil,
        },
        {
            &{"https", "foo.com", "/", "", "", "https://foo.com/", 443},
            "https://foo.com/",
            nil,
        },
        {
            &{"https", "foo.com", "", "?foo=bar", "", "https://foo.com?foo=bar", 443},
            "https://foo.com?foo=bar",
            nil,
        },
        {
            &{"https", "foo.com", "", "", "#foo", "https://foo.com#foo", 443},
            "https://foo.com#foo",
            nil,
        },
        {
            &{},
            "0https://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            &{},
            "+https://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            &{},
            "-https://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            &{},
            ".https://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            &{},
            "://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            &{},
            " https://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            &{},
            "ht tps://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            &{},
            "ht_tps://foo.com/bar?foo=bar#foo",
            .Scheme_Not_Found,
        },
        {
            &{"ws", "", "", "", "", "", 0},
            "ws://foo.com/bar?foo=bar#foo",
            .Invalid_Scheme,
        },
        {
            &{"https", "", "", "", "", "", 443},
            "https://.foo.com/bar?foo=bar#foo",
            .Host_Not_Found,
        },
        {
            &{"https", "", "", "", "", "", 443},
            "https://foo.com./bar?foo=bar#foo",
            .Host_Not_Found,
        },
        {
            &{"https", "", "", "", "", "", 443},
            "https://-foo.com/bar?foo=bar#foo",
            .Host_Not_Found,
        },
        {
            &{"https", "", "", "", "", "", 443},
            "https://foo.com-/bar?foo=bar#foo",
            .Host_Not_Found,
        },
        {
            &{"https", "", "", "", "", "", 443},
            "https://foo/bar?foo=bar#foo",
            .Host_Not_Found,
        },
        {
            &{"https", "", "", "", "", "", 443},
            "https://f oo.com/bar?foo=bar#foo",
            .Host_Not_Found,
        },
        {
            &{"https", "", "", "", "", "", 443},
            "https://f_oo.com/bar?foo=bar#foo",
            .Host_Not_Found,
        },

    }
    for test, _ in tests {
        url := url_init()
        defer url_free(url)
        err := url_parse(url, test.raw_url)
        testing.expect_value(t, url.scheme, test.url.scheme)
        testing.expect_value(t, url.host, test.url.host)
        testing.expect_value(t, url.path, test.url.path)
        testing.expect_value(t, url.query, test.url.query)
        testing.expect_value(t, url.fragment, test.url.fragment)
        testing.expect_value(t, url.raw, test.url.raw)
        testing.expect_value(t, url.port, test.url.port)
        testing.expect_value(t, err, test.err)
    }
}

@(test)
test_request_to_str :: proc(t: ^testing.T) {
    tests := []struct{method: Request_Method, url: ^Url, headers: map[string]string, body, res: string}{
        {
            .Post,
            &{"http", "foo.com", "/", "", "", "http://foo.com/", 80},
            nil,
            "",
            "POST / HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
        },
        {
            .Post,
            &{"https", "foo.com", "/", "", "", "https://foo.com/", 443},
            nil,
            "",
            "POST / HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
        },
        {
            .Post,
            &{"https", "foo.com", "/", "", "", "https://foo.com/", 443},
            nil,
            `{"foo": "bar"}`,
            "POST / HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\n\r\n" + `{"foo": "bar"}`,
        },
        {
            .Get,
            &{"https", "foo.com", "/", "", "", "https://foo.com/", 443},
            nil,
            "",
            "GET / HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
        },
        {
            .Get,
            &{"https", "foo.com", "/bar", "", "", "https://foo.com/bar", 443},
            nil,
            "",
            "GET /bar HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
        },
        {
            .Get,
            &{"https", "foo.com", "/bar", "?foo=bar", "", "https://foo.com/bar?foo=bar", 443},
            nil,
            "",
            "GET /bar?foo=bar HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
        },
        {
            .Get,
            &{"https", "foo.com", "/bar", "?foo=bar", "#foo", "https://foo.com/bar?foo=bar#foo", 443},
            nil,
            "",
            "GET /bar?foo=bar#foo HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
        },
        {
            .Get,
            &{"https", "foo.com", "/", "", "", "https://foo.com/", 443},
            {"Authorization" = "123"},
            "",
            "GET / HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\nAuthorization: 123\r\n\r\n",
        },
        {
            .Get,
            &{"https", "foo.com", "/", "", "", "https://foo.com/", 443},
            {"Authorization" = ""},
            "",
            "GET / HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\nAuthorization: \r\n\r\n",
        },
        {
            .Put,
            &{"https", "foo.com", "/", "", "", "https://foo.com/", 443},
            nil,
            "",
            "PUT / HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
        },
        {
            .Patch,
            &{"https", "foo.com", "/", "", "", "https://foo.com/", 443},
            nil,
            "",
            "PATCH / HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
        },
        {
            .Delete,
            &{"https", "foo.com", "/", "", "", "https://foo.com/", 443},
            nil,
            "",
            "DELETE / HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
        },
        {
            .Head,
            &{"https", "foo.com", "/", "", "", "https://foo.com/", 443},
            nil,
            "",
            "HEAD / HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
        },
        {
            .Options,
            &{"https", "foo.com", "/", "", "", "https://foo.com/", 443},
            nil,
            "",
            "OPTIONS / HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
        },
    }
    for test, _ in tests {
        req := request_init(test.method, test.url, transmute([]u8)test.body)
        defer request_free(req)
        req.headers = test.headers
        testing.expect_value(t, _request_to_str(req), test.res)
    }
}

@(test)
test_response_parse :: proc(t: ^testing.T) {
    body : string : `{"foo": "bar"}`
    tests := []struct{res: ^Response, data: string, err: Response_Error}{
        {
            &{{"Host" = "foo.com", "Connection" = "close", "Content-Length" = "14"}, "HTTP/1.1", "OK", transmute([]u8)body, 200},
            "HTTP/1.1 200 OK\r\nHost: foo.com\r\nConnection: close\r\nContent-Length: 14\r\n\r\n" + body,
            .None,
        },
        {
            &{{"Host" = "foo.com", "Connection" = "close"}, "HTTP/1.1", "OK", {}, 200},
            "HTTP/1.1 200 OK\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
            .None,
        },
        {
            &{{"Host" = "foo.com", "Connection" = ""}, "HTTP/1.1", "OK", {}, 200},
            "HTTP/1.1 200 OK\r\nHost: foo.com\r\nConnection: \r\n\r\n",
            .None,
        },
        {
            &{nil, "", "", {}, 0},
            "Host: foo.com\r\nConnection: close\r\n\r\n",
            .Status_Line_Not_Found,
        },
        {
            &{nil, "", "", {}, 0},
            "HTTP/1.1 200\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
            .Invalid_Status_Line,
        },
        {
            &{nil, "HTTP/1.1", "OK", {}, 200},
            "HTTP/1.1 200 OK\r\n: foo.com\r\n\r\n",
            .Invalid_Header,
        },
        {
            &{nil, "HTTP/1.1", "OK", {}, 200},
            "HTTP/1.1 200 OK\r\n:\r\n\r\n",
            .Invalid_Header
        },
    }
    for test, _ in tests {
        req := request_init(.Get, &{"https", "foo.com", "/", "", "", "https://foo.com/", 443}, nil)
        defer request_free(req)
        defer delete(test.res.headers)
        err := _response_parse(req.res, test.data)
        for key, val in req.res.headers {
            testing.expect_value(t, val, test.res.headers[key])
        }
        testing.expect_value(t, req.res.version, test.res.version)
        testing.expect_value(t, req.res.reason, test.res.reason)
        testing.expect_value(t, string(req.res.body), string(test.res.body))
        testing.expect_value(t, req.res.status, test.res.status)
        testing.expect_value(t, err, test.err)
    }
}

