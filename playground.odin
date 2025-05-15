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

// [scheme]://[host]/[path]?[query]
//
// [scheme] = http | https  ✓
// [host] = example.com     ✓
// [path] = foo             ✓
// [query] = ?foo=bar       ✓
// [fragment] = #foo        ✓


// Reports whether str contains any ASCII control character. 
_string_contains_control_character :: proc(str: string) -> (ok: bool) {
    for _, idx in str {
        if str[idx] < ' ' || str[idx] == 0x7f {
            return true
        }
    }
    return false
}

// Provided url can be in the form of scheme:path, if so, return scheme and remainder,
// otherwise return empty string and remainder. Scheme must be ([a-zA-Z][a-zA-Z0-9+-.]*).
_extract_scheme_from_url :: proc(raw_url: string) -> (scheme, remainder: string, ok: bool) {
    for char, idx in raw_url {
        switch {
        case 'a' <= char && char <= 'z' || 'A' <= char && char <= 'Z':
            continue

        case '0' <= char && char <= '9' || char == '+' || char == '-' || char == '.': 
            // [0-9+-.] found at the beginning
            if idx == 0 {
                return "", raw_url, false
            }
            
        case char == ':':
            if idx == 0 {
                // colon found at the beginning
                return "", raw_url, false
            }
            return raw_url[:idx], raw_url[idx+1:], true

        case:
            // invalid character found
            return "", raw_url, false
        }
    }
    return "", raw_url, false
}

_extract_host_from_url :: proc(raw_url: string) -> (host, remainder: string, ok: bool) {
    url := strings.trim_prefix(raw_url, "//")
    tld_idx, hyphen_idx: int

    for char, idx in url {
        switch {
        case 'a' <= char && char <= 'z' || 'A' <= char && char <= 'Z' || '0' <= char && char <= '9':
            continue

        case char == '-':
            if idx == 0 || idx == len(url)-1 {
                // hyphen found at the beginning or end 
                return "", raw_url, false 
            }
            hyphen_idx = idx

        case char == '.':
            if idx == 0 || idx == len(url)-1 {
                // dot found at the beginning or end
                return "", raw_url, false
            }
            tld_idx = idx

        case char == '/':
            if idx == 0 || hyphen_idx == idx-1 || tld_idx == idx-1 {
                // slash found at the beginning or after hyphen/dot
                return "", raw_url, false
            }

            if tld_idx != 0 {
                return url[:idx], url[idx:], true
            }

        case:
            // invalid character found
            return "", raw_url, false
        }
    }
    return "", raw_url, false
}

_percent_encode_url :: proc(raw_url: string) -> (path: string) {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    for char, idx in raw_url {
        switch {
        case char == ' ':
            strings.write_string(&builder, "%20")

        case char == ';':
            strings.write_string(&builder, "%3B")

        case char == ':':
            strings.write_string(&builder, "%3A")

        case char == '[':
            strings.write_string(&builder, "%5B")

        case char == ']':
            strings.write_string(&builder, "%5D")

        case char == '{':
            strings.write_string(&builder, "%7B")

        case char == '}':
            strings.write_string(&builder, "%7D")

        case char == '<':
            strings.write_string(&builder, "%3C")

        case char == '>':
            strings.write_string(&builder, "%3E")

        case char == '\\':
            strings.write_string(&builder, "%5C")

        case char == '^':
            strings.write_string(&builder, "%5E")

        case char == '`':
            strings.write_string(&builder, "%60")

        case char == '"':
            strings.write_string(&builder, "%22")

        case:
            strings.write_rune(&builder, char)
        }
    }
    return strings.to_string(builder)
}

parse_http_url :: proc(raw_url: string) -> (res: ^HttpUrl, ok: bool) {
    if ok := _string_contains_control_character(raw_url); ok {
        return nil, false
    }
    
    url := new(HttpUrl)
    remainder: string

    url.scheme, remainder, ok = _extract_scheme_from_url(raw_url)
    if !ok {
        return nil, false
    }

    url.host, remainder, ok = _extract_host_from_url(remainder)
    if !ok {
        return nil, false
    }

    // TODO: move this to a proc
    query_idx := strings.index(remainder, "?")
    fragment_idx := strings.index(remainder, "#")

    switch {
    case query_idx != -1 && fragment_idx != -1:
        url.path = strings.cut(remainder, 0, query_idx)
        url.fragment = strings.cut(remainder, fragment_idx, 0)
        cut_length := len(remainder) - len(url.path) - len(url.fragment)
        url.query = strings.cut(remainder, query_idx, cut_length)

    case query_idx != -1 && fragment_idx == -1:
        url.path = strings.cut(remainder, 0, query_idx)
        url.query = strings.cut(remainder, query_idx, 0)

    case query_idx == -1 && fragment_idx != -1:
        url.path = strings.cut(remainder, 0, fragment_idx)
        url.fragment = strings.cut(remainder, fragment_idx, 0) 

    case:
        url.path = remainder
    }

    return url, true
}

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
    url, _ := parse_http_url("http://foo.com/bar?foo=bar#foo")
    log.infof("url: %v\n", url)
    defer free(url)

    url2, _ := parse_http_url("http://foo.com/bar?foo=bar")
    log.infof("url: %v\n", url2)
    defer free(url2)
    
    url3, _ := parse_http_url("http://foo.com/bar#foo")
    log.infof("url: %v\n", url3)
    defer free(url3)

    url4, _ := parse_http_url("http://foo.com/bar")
    log.infof("url: %v\n", url4)
    defer free(url4)

    url5, _ := parse_http_url("http://foo.com/")
    log.infof("url: %v\n", url5)
    defer free(url5)
}

