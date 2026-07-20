#!/usr/bin/env bash
# Read-only local web server target discovery helpers.

if [[ -n "${MST_DISCOVER_LIB_LOADED:-}" ]]; then
    return
fi
readonly MST_DISCOVER_LIB_LOADED=1

MST_DISCOVER_NGINX_DIR="${MST_DISCOVER_NGINX_DIR:-/etc/nginx}"
MST_DISCOVER_APACHE_DIR="${MST_DISCOVER_APACHE_DIR:-/etc/apache2}"

mst_discover_clean_value() {
    local value="${1:-}"
    value="${value%%#*}"
    value="${value%;}"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

mst_discover_server_name_allowed() {
    case "${1:-}" in
        ""|_|localhost|default_server|\*.*) return 1 ;;
        *) return 0 ;;
    esac
}

mst_discover_emit_if_valid() {
    local server_name="${1:-}"
    local document_root="${2:-}"

    server_name="$(mst_discover_clean_value "${server_name}")"
    document_root="$(mst_discover_clean_value "${document_root}")"
    mst_discover_server_name_allowed "${server_name}" || return 0
    [[ -d "${document_root}" ]] || return 0
    printf '%s|%s\n' "${server_name}" "${document_root}"
}

mst_discover_parse_nginx_file() {
    local file_path="${1:?file required}"
    awk '
        function clean(value) {
            sub(/#.*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            sub(/;$/, "", value)
            gsub(/^["'\''"]|["'\''"]$/, "", value)
            return value
        }
        {
            line = $0
            sub(/#.*/, "", line)
            if (line ~ /(^|[[:space:]])server[[:space:]]*\{/) {
                in_block = 1
                depth = 0
                server_name = ""
                root = ""
            }
            if (in_block) {
                if (server_name == "" && line ~ /server_name[[:space:]]+[^;]+;/) {
                    value = line
                    sub(/^.*server_name[[:space:]]+/, "", value)
                    sub(/;.*/, "", value)
                    split(clean(value), names, /[[:space:]]+/)
                    server_name = names[1]
                }
                if (root == "" && line ~ /root[[:space:]]+[^;]+;/) {
                    value = line
                    sub(/^.*root[[:space:]]+/, "", value)
                    sub(/;.*/, "", value)
                    root = clean(value)
                }
                depth += gsub(/\{/, "{", line)
                depth -= gsub(/\}/, "}", line)
                if (depth <= 0) {
                    print server_name "|" root
                    in_block = 0
                }
            }
        }
    ' "${file_path}" 2>/dev/null
}

mst_discover_parse_apache_file() {
    local file_path="${1:?file required}"
    awk '
        function clean(value) {
            sub(/#.*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^["'\''"]|["'\''"]$/, "", value)
            return value
        }
        /^[[:space:]]*<VirtualHost([[:space:]]|>)/ {
            in_block = 1
            server_name = ""
            root = ""
        }
        in_block {
            if (server_name == "" && $1 == "ServerName") {
                server_name = clean($2)
            }
            if (root == "" && $1 == "DocumentRoot") {
                root = clean($2)
            }
            if ($0 ~ /^[[:space:]]*<\/VirtualHost>/) {
                print server_name "|" root
                in_block = 0
            }
        }
    ' "${file_path}" 2>/dev/null
}

mst_discover_nginx_files() {
    local nginx_dir="${MST_DISCOVER_NGINX_DIR:-/etc/nginx}"
    local sites_enabled="${nginx_dir}/sites-enabled"
    local conf_d="${nginx_dir}/conf.d"
    local file_path canonical_path canonical_nginx

    canonical_nginx="$(readlink -f -- "${nginx_dir}" 2>/dev/null || true)"
    if [[ -d "${sites_enabled}" ]]; then
        while IFS= read -r file_path; do
            [[ -f "${file_path}" && -r "${file_path}" ]] || continue
            canonical_path="$(readlink -f -- "${file_path}" 2>/dev/null || true)"
            [[ -n "${canonical_path}" && -n "${canonical_nginx}" ]] || continue
            case "${canonical_path}" in
                "${canonical_nginx}"/*) printf '%s\n' "${file_path}" ;;
            esac
        done < <(find "${sites_enabled}" -maxdepth 1 \( -type f -o -type l \) -print 2>/dev/null | sort)
    fi
    if [[ -d "${conf_d}" ]]; then
        while IFS= read -r file_path; do
            [[ -f "${file_path}" && -r "${file_path}" ]] || continue
            printf '%s\n' "${file_path}"
        done < <(find "${conf_d}" -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null | sort)
    fi
}

mst_discover_apache_files() {
    local apache_dir="${MST_DISCOVER_APACHE_DIR:-/etc/apache2}"
    local sites_enabled="${apache_dir}/sites-enabled"
    local file_path

    [[ -d "${sites_enabled}" ]] || return 0
    while IFS= read -r file_path; do
        [[ -f "${file_path}" && -r "${file_path}" ]] || continue
        printf '%s\n' "${file_path}"
    done < <(find "${sites_enabled}" -maxdepth 1 \( -type f -o -type l \) -print 2>/dev/null | sort)
}

mst_discover_web_sites() {
    local nginx_dir="${MST_DISCOVER_NGINX_DIR:-/etc/nginx}"
    local apache_dir="${MST_DISCOVER_APACHE_DIR:-/etc/apache2}"
    local file_path line server_name document_root seen_names=""

    if [[ -d "${nginx_dir}" ]]; then
        while IFS= read -r file_path; do
            while IFS='|' read -r server_name document_root || [[ -n "${server_name:-}${document_root:-}" ]]; do
                line="$(mst_discover_emit_if_valid "${server_name:-}" "${document_root:-}")"
                [[ -n "${line}" ]] || continue
                server_name="${line%%|*}"
                case "|${seen_names}|" in
                    *"|${server_name}|"*) continue ;;
                esac
                seen_names="${seen_names}|${server_name}"
                printf '%s\n' "${line}"
            done < <(mst_discover_parse_nginx_file "${file_path}")
        done < <(mst_discover_nginx_files)
    elif [[ -d "${apache_dir}/sites-enabled" ]]; then
        while IFS= read -r file_path; do
            while IFS='|' read -r server_name document_root || [[ -n "${server_name:-}${document_root:-}" ]]; do
                line="$(mst_discover_emit_if_valid "${server_name:-}" "${document_root:-}")"
                [[ -n "${line}" ]] || continue
                server_name="${line%%|*}"
                case "|${seen_names}|" in
                    *"|${server_name}|"*) continue ;;
                esac
                seen_names="${seen_names}|${server_name}"
                printf '%s\n' "${line}"
            done < <(mst_discover_parse_apache_file "${file_path}")
        done < <(mst_discover_apache_files)
    fi
    return 0
}

mst_discover_site_is_wordpress() {
    local document_root="${1:?document root required}"
    local canonical_root parent_config canonical_parent

    [[ -d "${document_root}" ]] || return 1
    if [[ -f "${document_root}/wp-config.php" && -r "${document_root}/wp-config.php" ]]; then
        return 0
    fi
    [[ -f "${document_root}/../wp-config.php" && -r "${document_root}/../wp-config.php" ]] || return 1
    canonical_root="$(readlink -f -- "${document_root}")" || return 1
    parent_config="$(readlink -f -- "${document_root}/../wp-config.php")" || return 1
    canonical_parent="$(dirname -- "${canonical_root}")"
    case "${parent_config}" in
        "${canonical_parent}/wp-config.php") return 0 ;;
        *) return 1 ;;
    esac
}
