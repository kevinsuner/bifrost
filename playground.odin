package main

import "core:strings"
import "core:testing"
import "core:log"

HttpUrl :: struct {
    scheme:     string,
    host:       string,
    path:       string,
    query:      string,
    fragment:   string,
}

Parse_Error :: enum i32 {
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

        case c == '/':
            if i == 0 || hyphen_pos == i-1 || period_pos == i-1 {
                // slash found at the beginning or after hyphen/period
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

@(test)
test_parse_http_url :: proc(t: ^testing.T) {
    url, err := parse_http_url("http://foo.com/bar?foo=bar#foo")
    log.infof("url: %v\n", url)
    log.infof("err: %v\n", err)
}

/*
@(test)
test_string_contains_control_character :: proc(t: ^testing.T) {
    ok := _string_contains_control_character("http://foo.com/bar?foo\nbar")
    testing.expect_value(t, ok, true)

    ok = _string_contains_control_character("http\r://foo.com/bar")
    testing.expect_value(t, ok, true)

    ok = _string_contains_control_character("http://foo\x7f.com/bar")
    testing.expect_value(t, ok, true)

    ok = _string_contains_control_character("http://foo.com/bar?foo&bar")
    testing.expect_value(t, ok, false)

    ok = _string_contains_control_character("http://foo.com/bar") 
    testing.expect_value(t, ok, false)
}

@(test)
test_extract_scheme_from_url :: proc(t: ^testing.T) {
    scheme, remainder, ok := _extract_scheme_from_url("http://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "http")
    testing.expect_value(t, remainder, "//foo.com/bar?foo=bar")
    testing.expect_value(t, ok, true)

    scheme, remainder, ok = _extract_scheme_from_url("https://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "https")
    testing.expect_value(t, remainder, "//foo.com/bar?foo=bar")
    testing.expect_value(t, ok, true)

    scheme, remainder, ok = _extract_scheme_from_url("ssh://foo@bar")
    testing.expect_value(t, scheme, "ssh")
    testing.expect_value(t, remainder, "//foo@bar")
    testing.expect_value(t, ok, true)

    scheme, remainder, ok = _extract_scheme_from_url("0http://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, "0http://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    scheme, remainder, ok = _extract_scheme_from_url("+http://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, "+http://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    scheme, remainder, ok = _extract_scheme_from_url("-http://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, "-http://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    scheme, remainder, ok = _extract_scheme_from_url(".http://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, ".http://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    scheme, remainder, ok = _extract_scheme_from_url("://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, "://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    scheme, remainder, ok = _extract_scheme_from_url(" http://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, " http://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    scheme, remainder, ok = _extract_scheme_from_url("ht tp://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, "ht tp://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    scheme, remainder, ok = _extract_scheme_from_url("ht_tp://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, "ht_tp://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)
}

@(test)
test_extract_host_from_url :: proc(t: ^testing.T) {
    host, remainder, ok := _extract_host_from_url("//foo.com/bar?foo=bar")
    testing.expect_value(t, host, "foo.com")
    testing.expect_value(t, remainder, "/bar?foo=bar")
    testing.expect_value(t, ok, true)

    host, remainder, ok = _extract_host_from_url("//foo.com/foo/bar?foo=bar")
    testing.expect_value(t, host, "foo.com")
    testing.expect_value(t, remainder, "/foo/bar?foo=bar")
    testing.expect_value(t, ok, true)

    host, remainder, ok = _extract_host_from_url("//.foo.com/bar?foo=bar")
    testing.expect_value(t, host, "")
    testing.expect_value(t, remainder, "//.foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    host, remainder, ok = _extract_host_from_url("//foo.com./bar?foo=bar")
    testing.expect_value(t, host, "")
    testing.expect_value(t, remainder, "//foo.com./bar?foo=bar")
    testing.expect_value(t, ok, false)

    host, remainder, ok = _extract_host_from_url("//-foo.com/bar?foo=bar")
    testing.expect_value(t, host, "")
    testing.expect_value(t, remainder, "//-foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    host, remainder, ok = _extract_host_from_url("//foo.com-/bar?foo=bar")
    testing.expect_value(t, host, "")
    testing.expect_value(t, remainder, "//foo.com-/bar?foo=bar")
    testing.expect_value(t, ok, false)

    host, remainder, ok = _extract_host_from_url("//foo/bar?foo=bar")
    testing.expect_value(t, host, "")
    testing.expect_value(t, remainder, "//foo/bar?foo=bar")
    testing.expect_value(t, ok, false)

    host, remainder, ok = _extract_host_from_url("//f oo.com/bar?foo=bar")
    testing.expect_value(t, host, "")
    testing.expect_value(t, remainder, "//f oo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    host, remainder, ok = _extract_host_from_url("//f_oo.com/bar?foo=bar")
    testing.expect_value(t, host, "")
    testing.expect_value(t, remainder, "//f_oo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)
}

@(test)
test_percent_encode_url :: proc(t: ^testing.T) {
    path := _percent_encode_url("/foo/bar?foo=bar")
    testing.expect_value(t, path, "/foo/bar?foo=bar")

    path = _percent_encode_url("/foo/bar?foo=123")
    testing.expect_value(t, path, "/foo/bar?foo=123")

    path = _percent_encode_url("/foo/bar?foo=bar&fizz=buzz")
    testing.expect_value(t, path, "/foo/bar?foo=bar&fizz=buzz")

    path = _percent_encode_url("/foo/bar?foo=bar&fizz=buzz+123")
    testing.expect_value(t, path, "/foo/bar?foo=bar&fizz=buzz+123")

    path = _percent_encode_url("/foo/bar?foo=bar&fizz=buzz#foo")
    testing.expect_value(t, path, "/foo/bar?foo=bar&fizz=buzz#foo")

    path = _percent_encode_url("/foo/bar-?foo=bar-")
    testing.expect_value(t, path, "/foo/bar-?foo=bar-")

    path = _percent_encode_url("/foo/bar_?foo=bar_")
    testing.expect_value(t, path, "/foo/bar_?foo=bar_")

    path = _percent_encode_url("/foo/bar.?foo=bar.")
    testing.expect_value(t, path, "/foo/bar.?foo=bar.")

    path = _percent_encode_url("/foo/bar~?foo=bar~")
    testing.expect_value(t, path, "/foo/bar~?foo=bar~")

    path = _percent_encode_url("/foo/bar ?foo=bar ")
    testing.expect_value(t, path, "/foo/bar%20?foo=bar%20")

    path = _percent_encode_url("/foo/bar;?foo=bar;")
    testing.expect_value(t, path, "/foo/bar%3B?foo=bar%3B")

    path = _percent_encode_url("/foo/bar:?foo=bar:")
    testing.expect_value(t, path, "/foo/bar%3A?foo=bar%3A")

    path = _percent_encode_url("/foo/bar[?foo=bar[")
    testing.expect_value(t, path, "/foo/bar%5B?foo=bar%5B")

    path = _percent_encode_url("/foo/bar]?foo=bar]")
    testing.expect_value(t, path, "/foo/bar%5D?foo=bar%5D")

    path = _percent_encode_url("/foo/bar{?foo=bar{")
    testing.expect_value(t, path, "/foo/bar%7B?foo=bar%7B")

    path = _percent_encode_url("/foo/bar}?foo=bar}")
    testing.expect_value(t, path, "/foo/bar%7D?foo=bar%7D")

    path = _percent_encode_url("/foo/bar<?foo=bar<")
    testing.expect_value(t, path, "/foo/bar%3C?foo=bar%3C")

    path = _percent_encode_url("/foo/bar>?foo=bar>")
    testing.expect_value(t, path, "/foo/bar%3E?foo=bar%3E")

    path = _percent_encode_url("/foo/bar\\?foo=bar\\",)
    testing.expect_value(t, path, "/foo/bar%5C?foo=bar%5C")

    path = _percent_encode_url("/foo/bar^?foo=bar^")
    testing.expect_value(t, path, "/foo/bar%5E?foo=bar%5E")

    path = _percent_encode_url("/foo/bar`?foo=bar`")
    testing.expect_value(t, path, "/foo/bar%60?foo=bar%60")

    path = _percent_encode_url(`/foo/bar"?foo=bar"`)
    testing.expect_value(t, path, "/foo/bar%22?foo=bar%22")
}

@(test)
test_parse_http_url :: proc(t: ^testing.T) {
    url, err := parse_http_url("http://foo.com/bar?foo=bar#foo")
    if err != Parse_Error.None {
        log.infof("err: %v\n", err) 
    }
    log.infof("url: %v\n", url)
}
*/
