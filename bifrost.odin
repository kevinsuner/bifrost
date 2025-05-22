package bifrost

import "core:fmt"
import "core:strings"
import "core:testing"

// TODO:
// - Parse HTTP url into an HttpUrl struct                              ✓
// - Create a proc to build an HTTP request string                      ✓
// - Parse HTTP response headers and body into an HttpResponse struct   ×
// - Create a proc to perform a dynamically allocated HTTP request      ×

HttpUrl :: struct {
    scheme:     string,
    host:       string,
    path:       string,
    query:      string,
    fragment:   string,
}

Parse_Error :: enum i8 {
    None,
    // Found an ASCII control character.
    Found_Control_Character,
    // Unable to extract scheme part of http url.
    Scheme_Not_Found,
    // Scheme is neither `http` nor `https`.
    Invalid_Scheme,
    // Unable to extract host part of http url.
    Host_Not_Found,
}

/*
Reports whether `str` contains any ASCII control character

Inputs:
- str: The input string

Returns:
- ok: A boolean indicating if any ASCII control character was found
*/
@(private)
_has_control_character :: proc(str: string) -> (ok: bool) {
    for _, i in str {
        if str[i] < ' ' || str[i] == 0x7f {
            return true
        }
    }
    return false
}

/*
Extracts the http scheme part from `str`

Inputs:
- str: The input string

Returns:
- res: The http scheme
- remainder: The rest of the string
- ok: A boolean indicating whether the http scheme was found or not
*/
@(private)
_extract_http_scheme :: proc(str: string) -> (res, remainder: string, ok: bool) {
    for c, i in str {
        switch {
        case 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z':
            continue

        case '0' <= c && c <= '9' || c == '+' || c == '-' || c == '.':
            if i == 0 {
                // [0-9+-.] found at the beginning
                return "", str, false
            }

        case c == ':':
            if i == 0 {
                // colon found at the beginning
                return "", str, false
            }
            return str[:i], str[i+1:], true

        case:
            // invalid character found
            return "", str, false
        }
    }
    return "", str, false
}

/*
Extracts the http host part from `str`

Inputs:
- str: The input string

Returns:
- res: The http host
- remainder: The rest of the string
- ok: A boolean indicating whether the http host was found or not
*/
@(private)
_extract_http_host :: proc(str: string) -> (res, remainder: string, ok: bool) {
    s := strings.trim_prefix(str, "//")
    hyphen_pos, period_pos: int

    for c, i in s {
        switch {
        case 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' || '0' <= c && c <= '9':
            continue

        case c == '-':
            if i == 0 || i == len(s)-1 {
                // hyphen found at the beginning or end
                return "", str, false
            }
            hyphen_pos = i

        case c == '.':
            if i == 0 || i == len(s)-1 {
                // period found at the beginning or end
                return "", str, false
            }
            period_pos = i

        case c == '/' || c == '?' || c == '#':
            if i == 0 || hyphen_pos == i-1 || period_pos == i-1 {
                // [/?#] found at the beginning or after hyphen/period
                return "", str, false
            }

            if period_pos != 0 {
                return s[:i], s[i:], true
            }

        case:
            // invalid character found
            return "", str, false
        }
    }
    return "", str, false
}

/*
Escapes specific characters from `str` using percent-encoding

Inputs:
- str: The input string

Returns:
- res: The percent-encoded string
*/
@(private)
_percent_encode_str :: proc(str: string) -> (res: string) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    for c, i in str {
        switch {
        case c == ' ':
            strings.write_string(&sb, "%20")

        case c == ';':
            strings.write_string(&sb, "%3B")

        case c == ':':
            strings.write_string(&sb, "%3A")

        case c == '[':
            strings.write_string(&sb, "%5B")

        case c == ']':
            strings.write_string(&sb, "%5D")

        case c == '{':
            strings.write_string(&sb, "%7B")

        case c == '}':
            strings.write_string(&sb, "%7D")

        case c == '<':
            strings.write_string(&sb, "%3C")

        case c == '>':
            strings.write_string(&sb, "%3E")

        case c == '\\':
            strings.write_string(&sb, "%5C")

        case c == '^':
            strings.write_string(&sb, "%5E")

        case c == '`':
            strings.write_string(&sb, "%60")

        case c == '"':
            strings.write_string(&sb, "%22")

        case:
            strings.write_rune(&sb, c)
        }
    }
    return strings.to_string(sb)
}

/*
Parses `str` into an `HttpUrl` struct

Inputs:
- str: The input string

Returns:
- res: An initialized `HttpUrl` struct
- err: An enumerated value from `Parse_Error`

Example:

    import "core:fmt"
    import "libs/bifrost"

    main :: proc() {
        fmt.printf("%v\n", bifrost.parse_http_url("http://foo.com/bar?foo=bar#foo"))
        fmt.printf("%v\n", bifrost.parse_http_url("http://foo.com/bar?foo=bar"))
        fmt.printf("%v\n", bifrost.parse_http_url("http://foo.com/bar"))
        fmt.printf("%v\n", bifrost.parse_http_url("http://foo.com/"))
    }

Output:

    HttpUrl{"http", "foo.com", "/bar", "?foo=bar", "#foo"}
    HttpUrl{"http", "foo.com", "/bar", "?foo=bar", ""}
    HttpUrl{"http", "foo.com", "/bar", "", ""}
    HttpUrl{"http", "foo.com", "/", "", ""}

*/
parse_http_url :: proc(str: string) -> (res: HttpUrl, err: Parse_Error) {
    ok := _has_control_character(str)
    if ok {
        return {}, .Found_Control_Character
    }

    remainder: string
    res.scheme, remainder, ok = _extract_http_scheme(str)
    if !ok {
        return {}, .Scheme_Not_Found
    }
    if res.scheme != "http" && res.scheme != "https" {
        return {}, .Invalid_Scheme
    }

    res.host, remainder, ok = _extract_http_host(remainder)
    if !ok {
        return {}, .Host_Not_Found
    }
    remainder = _percent_encode_str(remainder)

    // extract fragment, query and path by going backwards through the remainder,
    // ok check is omitted as the values are optional
    res.fragment, _ = strings.substring(remainder, strings.index(remainder, "#"), len(remainder))
    res.query, _ = strings.substring(remainder, strings.index(remainder, "?"), len(remainder)-len(res.fragment))
    res.path, _ = strings.substring(remainder, 0, len(remainder)-len(res.query)-len(res.fragment))
    return res, .None
}

HttpHeader :: struct {
    key: string,
    val: string,
}

HttpMethod :: enum i8 {
    Get,
    Post,
}

@(private)
_http_method_str := [HttpMethod]string{
    .Get    = "GET",
    .Post   = "POST",
}

/*
Builds an HTTP request string

Inputs:
- method: An enumerated value from `HttpMethod`
- url: An initialized `HttpUrl` struct
- headers: An optional slice of `HttpHeader` structs
- body: The bytes for the request body

Returns:
- res: A slice of bytes representing an HTTP request

Example

    import "core:fmt"
    import "libs/bifrost"

    main :: proc() {
        url, _ := bifrost.parse_http_url("http://foo.com/")
        fmt.printf("\n%s\n", bifrost.build_http_request(.Get, url, nil, []u8{}))
    }

Output:

    GET http://foo.com/ HTTP/1.1
    Host: http://foo.com/
    Connection: keep-alive

*/
build_http_request :: proc(method: HttpMethod, url: HttpUrl, headers: []HttpHeader, body: []u8) -> (res: []u8) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    raw_url := fmt.tprintf("%s://%s%s%s%s", url.scheme, url.host, url.path, url.query, url.fragment)
    fmt.sbprintf(&sb, "%s %s HTTP/1.1\r\n", _http_method_str[method], raw_url)

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
test_has_control_character :: proc(t: ^testing.T) {
    tests := []struct{str: string, ok: bool}{
        { "http://foo.com/bar?foo=bar#foo", false },
        { "http://foo.com/bar?foo=bar#foo\n", true },
        { "http://foo.com/bar?foo=bar#foo\r", true },
        { "http://foo.com/bar?foo=bar#foo\x7f", true },
    }
    for test, _ in tests {
        ok := _has_control_character(test.str)
        testing.expect_value(t, ok, test.ok)
    }
}

@(test)
test_extract_http_scheme :: proc(t: ^testing.T) {
    tests := []struct{str, res, remainder: string, ok: bool}{
        { "http://foo.com/bar?foo=bar#foo", "http", "//foo.com/bar?foo=bar#foo", true },
        { "https://foo.com/bar?foo=bar#foo", "https", "//foo.com/bar?foo=bar#foo", true },
        { "0http://foo.com/bar?foo=bar#foo", "", "0http://foo.com/bar?foo=bar#foo", false },
        { "+http://foo.com/bar?foo=bar#foo", "", "+http://foo.com/bar?foo=bar#foo", false },
        { "-http://foo.com/bar?foo=bar#foo", "", "-http://foo.com/bar?foo=bar#foo", false },
        { ".http://foo.com/bar?foo=bar#foo", "", ".http://foo.com/bar?foo=bar#foo", false },
        { "://foo.com/bar?foo=bar#foo", "", "://foo.com/bar?foo=bar#foo", false },
        { " http://foo.com/bar?foo=bar#foo", "", " http://foo.com/bar?foo=bar#foo", false },
        { "ht tp://foo.com/bar?foo=bar#foo", "", "ht tp://foo.com/bar?foo=bar#foo", false },
        { "ht_tp://foo.com/bar?foo=bar#foo", "", "ht_tp://foo.com/bar?foo=bar#foo", false },
    }
    for test, _ in tests {
        res, remainder, ok := _extract_http_scheme(test.str)
        testing.expect_value(t, res, test.res)
        testing.expect_value(t, remainder, test.remainder)
        testing.expect_value(t, ok, test.ok)
    }
}

@(test)
test_extract_http_host :: proc(t: ^testing.T) {
    tests := []struct{str, res, remainder: string, ok: bool}{
        { "//foo.com/bar?foo=bar#foo", "foo.com", "/bar?foo=bar#foo", true },
        { "//foo.bar.com/bar?foo=bar#foo", "foo.bar.com", "/bar?foo=bar#foo", true },
        { "//.foo.com/bar?foo=bar#foo", "", "//.foo.com/bar?foo=bar#foo", false },
        { "//foo.com./bar?foo=bar#foo", "", "//foo.com./bar?foo=bar#foo", false },
        { "//-foo.com/bar?foo=bar#foo", "", "//-foo.com/bar?foo=bar#foo", false },
        { "//foo.com-/bar?foo=bar#foo", "", "//foo.com-/bar?foo=bar#foo", false },
        { "//foo/bar?foo=bar#foo", "", "//foo/bar?foo=bar#foo", false },
        { "//f oo.com/bar?foo=bar#foo", "", "//f oo.com/bar?foo=bar#foo", false },
        { "//f_oo.com/bar?foo=bar#foo", "", "//f_oo.com/bar?foo=bar#foo", false },
    }
    for test, _ in tests {
        res, remainder, ok := _extract_http_host(test.str)
        testing.expect_value(t, res, test.res)
        testing.expect_value(t, remainder, test.remainder)
        testing.expect_value(t, ok, test.ok)
    }
}

@(test)
test_percent_encode_str :: proc(t: ^testing.T) {
    tests := []struct{str, res: string}{
        { "/bar?foo=bar #foo", "/bar?foo=bar%20#foo" },
        { "/bar?foo=bar;#foo", "/bar?foo=bar%3B#foo" },
        { "/bar?foo=bar:#foo", "/bar?foo=bar%3A#foo" },
        { "/bar?foo=bar[#foo", "/bar?foo=bar%5B#foo" },
        { "/bar?foo=bar]#foo", "/bar?foo=bar%5D#foo" },
        { "/bar?foo=bar{#foo", "/bar?foo=bar%7B#foo" },
        { "/bar?foo=bar}#foo", "/bar?foo=bar%7D#foo" },
        { "/bar?foo=bar<#foo", "/bar?foo=bar%3C#foo" },
        { "/bar?foo=bar>#foo", "/bar?foo=bar%3E#foo" },
        { "/bar?foo=bar\\#foo", "/bar?foo=bar%5C#foo" },
        { "/bar?foo=bar^#foo", "/bar?foo=bar%5E#foo" },
        { "/bar?foo=bar`#foo", "/bar?foo=bar%60#foo" },
        { `/bar?foo=bar"#foo`, "/bar?foo=bar%22#foo" },
    }
    for test, _ in tests {
        res := _percent_encode_str(test.str)
        testing.expect_value(t, res, test.res)
    }
}

@(test)
test_parse_http_url :: proc(t: ^testing.T) {
    tests := []struct{str: string, res: HttpUrl, err: Parse_Error}{
        { "http://foo.com/bar?foo=bar&bar=foo#foo", { "http", "foo.com", "/bar", "?foo=bar&bar=foo", "#foo" }, .None },
        { "http://foo.bar.com/bar?foo=bar#foo", { "http", "foo.bar.com", "/bar", "?foo=bar", "#foo" }, .None },
        { "http://foo.com/bar?foo=bar#foo", { "http", "foo.com", "/bar", "?foo=bar", "#foo" }, .None },
        { "http://foo.com/bar?foo=bar #foo", { "http", "foo.com", "/bar", "?foo=bar%20", "#foo" }, .None },
        { "http://foo.com/bar?foo=bar;#foo", { "http", "foo.com", "/bar", "?foo=bar%3B", "#foo" }, .None },
        { "http://foo.com/bar?foo=bar:#foo", { "http", "foo.com", "/bar", "?foo=bar%3A", "#foo" }, .None },
        { "http://foo.com/bar?foo=bar[#foo", { "http", "foo.com", "/bar", "?foo=bar%5B", "#foo" }, .None },
        { "http://foo.com/bar?foo=bar]#foo", { "http", "foo.com", "/bar", "?foo=bar%5D", "#foo" }, .None },
        { "http://foo.com/bar?foo=bar{#foo", { "http", "foo.com", "/bar", "?foo=bar%7B", "#foo" }, .None },
        { "http://foo.com/bar?foo=bar}#foo", { "http", "foo.com", "/bar", "?foo=bar%7D", "#foo" }, .None },
        { "http://foo.com/bar?foo=bar<#foo", { "http", "foo.com", "/bar", "?foo=bar%3C", "#foo" }, .None },
        { "http://foo.com/bar?foo=bar>#foo", { "http", "foo.com", "/bar", "?foo=bar%3E", "#foo" }, .None },
        { "http://foo.com/bar?foo=bar\\#foo", { "http", "foo.com", "/bar", "?foo=bar%5C", "#foo" }, .None },
        { "http://foo.com/bar?foo=bar^#foo", { "http", "foo.com", "/bar", "?foo=bar%5E", "#foo" }, .None },
        { "http://foo.com/bar?foo=bar`#foo", { "http", "foo.com", "/bar", "?foo=bar%60", "#foo" }, .None },
        { `http://foo.com/bar?foo=bar"#foo`, { "http", "foo.com", "/bar", "?foo=bar%22", "#foo" }, .None },
        { "http://foo.com/bar?foo=bar", { "http", "foo.com", "/bar", "?foo=bar", "" }, .None },
        { "http://foo.com/bar#foo", { "http", "foo.com", "/bar", "", "#foo" }, .None },
        { "http://foo.com/bar", { "http", "foo.com", "/bar", "", "" }, .None },
        { "http://foo.com/", { "http", "foo.com", "/", "", "" }, .None },
        { "http://foo.com?foo=bar", { "http", "foo.com", "", "?foo=bar", "" }, .None },
        { "http://foo.com#foo", { "http", "foo.com", "", "", "#foo" }, .None },
        { "https://foo.com/bar?foo=bar#foo", { "https", "foo.com", "/bar", "?foo=bar", "#foo" }, .None },
        { "0http://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found },
        { "+http://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found },
        { "-http://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found },
        { ".http://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found },
        { "://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found },
        { " http://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found },
        { "ht tp://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found },
        { "ht_tp://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found },
        { "ws://foo.com/bar?foo=bar#foo", {}, .Invalid_Scheme },
        { "http://.foo.com/bar?foo=bar#foo", {}, .Host_Not_Found },
        { "http://foo.com./bar?foo=bar#foo", {}, .Host_Not_Found },
        { "http://-foo.com/bar?foo=bar#foo", {}, .Host_Not_Found },
        { "http://foo.com-/bar?foo=bar#foo", {}, .Host_Not_Found },
        { "http://foo/bar?foo=bar#foo", {}, .Host_Not_Found },
        { "http://f oo.com/bar?foo=bar#foo", {}, .Host_Not_Found },
        { "http://f_oo.com/bar?foo=bar#foo", {}, .Host_Not_Found },
    }
    for test, _ in tests {
        res, err := parse_http_url(test.str)
        testing.expect_value(t, res, test.res)
        testing.expect_value(t, err, test.err)
    }
}

@(test)
test_build_request :: proc(t: ^testing.T) {
    tests := []struct{method: HttpMethod, url: HttpUrl, headers: []HttpHeader, body: []u8, res: string}{
        {
            .Get, HttpUrl{"http", "foo.com", "/", "", ""}, nil, nil,
            "GET http://foo.com/ HTTP/1.1\r\nHost: http://foo.com/\r\nConnection: keep-alive\r\n\r\n",
        },
    }
    for test, _ in tests {
        request := build_http_request(test.method, test.url, test.headers, test.body)
        testing.expect_value(t, string(request), test.res)
    }
}

