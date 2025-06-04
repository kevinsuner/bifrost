#+feature dynamic-literals
package bifrost

import "core:testing"

@(test)
test_has_control_character :: proc(t: ^testing.T) {
    tests := []struct{str: string, err: URL_Error}{
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
    tests := []struct{str, res, rest: string, err: URL_Error}{
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
    tests := []struct{str, res, rest: string, err: URL_Error}{
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
    tests := []struct{str, res: string}{
        {
            "/bar?foo=bar #foo",
            "/bar?foo=bar%20#foo",
        },
        {
            "/bar?foo=bar;#foo",
            "/bar?foo=bar%3B#foo",
        },
        {
            "/bar?foo=bar:#foo",
            "/bar?foo=bar%3A#foo",
        },
        {
            "/bar?foo=bar[#foo",
            "/bar?foo=bar%5B#foo",
        },
        {
            "/bar?foo=bar]#foo",
            "/bar?foo=bar%5D#foo",
        },
        {
            "/bar?foo=bar{#foo",
            "/bar?foo=bar%7B#foo",
        },
        {
            "/bar?foo=bar}#foo",
            "/bar?foo=bar%7D#foo",
        },
        {
            "/bar?foo=bar<#foo",
            "/bar?foo=bar%3C#foo",
        },
        {
            "/bar?foo=bar>#foo",
            "/bar?foo=bar%3E#foo",
        },
        {
            "/bar?foo=bar\\#foo",
            "/bar?foo=bar%5C#foo",
        },
        {
            "/bar?foo=bar^#foo",
            "/bar?foo=bar%5E#foo",
        },
        {
            "/bar?foo=bar`#foo",
            "/bar?foo=bar%60#foo",
        },
        {
            `/bar?foo=bar"#foo`,
            "/bar?foo=bar%22#foo",
        },
    }
    for test, _ in tests {
        testing.expect_value(t, _percent_encode_str(test.str), test.res)
    }
}

@(test)
test_parse_url :: proc(t: ^testing.T) {
    tests := []struct{str: string, url: ^Url, err: URL_Error}{
        {
            "http://foo.com/bar?foo=bar&bar=foo#foo",
            &{"http", "foo.com", "/bar", "?foo=bar&bar=foo", "#foo", "http://foo.com/bar?foo=bar&bar=foo#foo", 80},
            .None,
        },
        {
            "https://foo.com/bar?foo=bar&bar=foo#foo",
            &{"https", "foo.com", "/bar", "?foo=bar&bar=foo", "#foo", "https://foo.com/bar?foo=bar&bar=foo#foo", 443},
            .None,
        },
        {
            "https://foo.bar.com/bar?foo=bar#foo",
            &{"https", "foo.bar.com", "/bar", "?foo=bar", "#foo", "https://foo.bar.com/bar?foo=bar#foo", 443},
            .None,
        },
        {
            "https://foo.com/bar?foo=bar#foo",
            &{"https", "foo.com", "/bar", "?foo=bar", "#foo", "https://foo.com/bar?foo=bar#foo", 443},
            .None,
        },
        {
            "https://foo.com/bar?foo=bar #foo",
            &{"https", "foo.com", "/bar", "?foo=bar%20", "#foo", "https://foo.com/bar?foo=bar #foo", 443},
            .None,
        },
        {
            "https://foo.com/bar?foo=bar;#foo",
            &{"https", "foo.com", "/bar", "?foo=bar%3B", "#foo", "https://foo.com/bar?foo=bar;#foo", 443},
            .None,
        },
        {
            "https://foo.com/bar?foo=bar:#foo",
            &{"https", "foo.com", "/bar", "?foo=bar%3A", "#foo", "https://foo.com/bar?foo=bar:#foo", 443},
            .None,
        },
        {
            "https://foo.com/bar?foo=bar[#foo",
            &{"https", "foo.com", "/bar", "?foo=bar%5B", "#foo", "https://foo.com/bar?foo=bar[#foo", 443},
            .None,
        },
        {
            "https://foo.com/bar?foo=bar]#foo",
            &{"https", "foo.com", "/bar", "?foo=bar%5D", "#foo", "https://foo.com/bar?foo=bar]#foo", 443},
            .None,
        },
        {
            "https://foo.com/bar?foo=bar{#foo",
            &{"https", "foo.com", "/bar", "?foo=bar%7B", "#foo", "https://foo.com/bar?foo=bar{#foo", 443},
            .None,
        },
        {
            "https://foo.com/bar?foo=bar}#foo",
            &{"https", "foo.com", "/bar", "?foo=bar%7D", "#foo", "https://foo.com/bar?foo=bar}#foo", 443},
            .None,
        },
        {
            "https://foo.com/bar?foo=bar<#foo",
            &{"https", "foo.com", "/bar", "?foo=bar%3C", "#foo", "https://foo.com/bar?foo=bar<#foo", 443},
            .None,
        },
        {
            "https://foo.com/bar?foo=bar>#foo",
            &{"https", "foo.com", "/bar", "?foo=bar%3E", "#foo", "https://foo.com/bar?foo=bar>#foo", 443},
            .None,
        },
        {
            "https://foo.com/bar?foo=bar\\#foo",
            &{"https", "foo.com", "/bar", "?foo=bar%5C", "#foo", "https://foo.com/bar?foo=bar\\#foo", 443 },
            .None,
        },
        {
            "https://foo.com/bar?foo=bar^#foo",
            &{"https", "foo.com", "/bar", "?foo=bar%5E", "#foo", "https://foo.com/bar?foo=bar^#foo", 443},
            .None,
        },
        {
            "https://foo.com/bar?foo=bar`#foo",
            &{"https", "foo.com", "/bar", "?foo=bar%60", "#foo", "https://foo.com/bar?foo=bar`#foo", 443},
            .None,
        },
        {
            `https://foo.com/bar?foo=bar"#foo`,
            &{"https", "foo.com", "/bar", "?foo=bar%22", "#foo", `https://foo.com/bar?foo=bar"#foo`, 443},
            .None,
        },
        {
            "https://foo.com/bar?foo=bar",
            &{"https", "foo.com", "/bar", "?foo=bar", "", "https://foo.com/bar?foo=bar", 443},
            .None,
        },
        {
            "https://foo.com/bar#foo",
            &{"https", "foo.com", "/bar", "", "#foo", "https://foo.com/bar#foo", 443},
            .None,
        },
        {
            "https://foo.com/bar",
            &{"https", "foo.com", "/bar", "", "", "https://foo.com/bar", 443},
            .None,
        },
        {
            "https://foo.com/",
            &{"https", "foo.com", "/", "", "", "https://foo.com/", 443},
            .None,
        },
        {
            "https://foo.com?foo=bar",
            &{"https", "foo.com", "", "?foo=bar", "", "https://foo.com?foo=bar", 443},
            .None,
        },
        {
            "https://foo.com#foo",
            &{"https", "foo.com", "", "", "#foo", "https://foo.com#foo", 443},
            .None,
        },
        {
            "0https://foo.com/bar?foo=bar#foo",
            &{},
            .Scheme_Not_Found,
        },
        {
            "+https://foo.com/bar?foo=bar#foo",
            &{},
            .Scheme_Not_Found,
        },
        {
            "-https://foo.com/bar?foo=bar#foo",
            &{},
            .Scheme_Not_Found,
        },
        {
            ".https://foo.com/bar?foo=bar#foo",
            &{},
            .Scheme_Not_Found,
        },
        {
            "://foo.com/bar?foo=bar#foo",
            &{},
            .Scheme_Not_Found,
        },
        {
            " https://foo.com/bar?foo=bar#foo",
            &{},
            .Scheme_Not_Found,
        },
        {
            "ht tps://foo.com/bar?foo=bar#foo",
            &{},
            .Scheme_Not_Found,
        },
        {
            "ht_tps://foo.com/bar?foo=bar#foo",
            &{},
            .Scheme_Not_Found,
        },
        {
            "ws://foo.com/bar?foo=bar#foo",
            &{"ws", "", "", "", "", "", 0},
            .Invalid_Scheme,
        },
        {
            "https://.foo.com/bar?foo=bar#foo",
            &{"https", "", "", "", "", "", 443},
            .Host_Not_Found,
        },
        {
            "https://foo.com./bar?foo=bar#foo",
            &{"https", "", "", "", "", "", 443},
            .Host_Not_Found,
        },
        {
            "https://-foo.com/bar?foo=bar#foo",
            &{"https", "", "", "", "", "", 443},
            .Host_Not_Found,
        },
        {
            "https://foo.com-/bar?foo=bar#foo",
            &{"https", "", "", "", "", "", 443},
            .Host_Not_Found,
        },
        {
            "https://foo/bar?foo=bar#foo",
            &{"https", "", "", "", "", "", 443},
            .Host_Not_Found,
        },
        {
            "https://f oo.com/bar?foo=bar#foo",
            &{"https", "", "", "", "", "", 443},
            .Host_Not_Found,
        },
        {
            "https://f_oo.com/bar?foo=bar#foo",
            &{"https", "", "", "", "", "", 443},
            .Host_Not_Found,
        },
    }
    for test, _ in tests {
        url := new(Url)
        err := parse_url(url, test.str)
        testing.expect_value(t, url.scheme, test.url.scheme)
        testing.expect_value(t, url.host, test.url.host)
        testing.expect_value(t, url.path, test.url.path)
        testing.expect_value(t, url.query, test.url.query)
        testing.expect_value(t, url.fragment, test.url.fragment)
        testing.expect_value(t, url.raw, test.url.raw)
        testing.expect_value(t, url.port, test.url.port)
        free(url)
    }
}

@(test)
test_build_request :: proc(t: ^testing.T) {
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
            "POST / HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\n\r\n" + `{"foo": "bar"}`
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
        res := _build_request(test.method, test.url, test.headers, transmute([]u8)test.body)
        testing.expect_value(t, string(res), test.res)
        delete(test.headers)
    }
}

@(test)
test_parse_response :: proc(t: ^testing.T) {
    body : string : `{"foo": "bar"}`
    tests := []struct{buf: string, res: ^Response, err: Response_Error}{
        {
            "HTTP/1.1 200 OK\r\nHost: foo.com\r\nConnection: close\r\n\r\n" + body,
            &{{"Host" = "foo.com", "Connection" = "close"}, "HTTP/1.1", "OK", transmute([]u8)body, 200},
            .None,
        },
        {
            "HTTP/1.1 200 OK\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
            &{{"Host" = "foo.com", "Connection" = "close"}, "HTTP/1.1", "OK", {}, 200},
            .None,
        },
        {
            "HTTP/1.1 200 OK\r\nHost: foo.com\r\nConnection: \r\n\r\n",
            &{{"Host" = "foo.com", "Connection" = ""}, "HTTP/1.1", "OK", {}, 200},
            .None,
        },
        {
            "HTTP/1.1 200 OK\r\n\r\n",
            &{nil, "HTTP/1.1", "OK", {}, 200},
            .None,
        },
        {
            "Host: foo.com\r\nConnection: close\r\n\r\n",
            &{nil, "", "", {}, 0},
            .Status_Line_Not_Found,
        },
        {
            "HTTP/1.1 200\r\nHost: foo.com\r\nConnection: close\r\n\r\n",
            &{nil, "", "", {}, 0},
            .Invalid_Status_Line,
        },
        {
            "HTTP/1.1 200 OK\r\n: foo.com\r\n\r\n",
            &{nil, "HTTP/1.1", "OK", {}, 200},
            .Invalid_Header,
        },
        {
            "HTTP/1.1 200 OK\r\n:\r\n\r\n",
            &{nil, "HTTP/1.1", "OK", {}, 200},
            .Invalid_Header,
        },
    }
    for test, _ in tests {
        res := new(Response)
        err := _parse_response(res, test.buf)
        for key, val in res.headers {
            testing.expect_value(t, val, test.res.headers[key])
        }
        testing.expect_value(t, res.version, test.res.version)
        testing.expect_value(t, res.reason, test.res.reason)
        testing.expect_value(t, string(res.body), string(test.res.body))
        testing.expect_value(t, res.status, test.res.status)
        testing.expect_value(t, err, test.err)
        delete(test.res.headers)
        delete(res.headers)
        free(res)
    }
}

