-- Minimal markdown → HTML renderer for nginx Lua
-- Handles wiki-flavor markdown: headers, bold, italic, code, links, lists, hr

local function escape(s)
    s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    return s
end

local function inline(s)
    -- Images ![alt](url)
    s = s:gsub("!%[([^%]]*)%]%(([^)]+)%)", '<img src="%2" alt="%1">')
    -- Links [text](url)
    s = s:gsub("%[([^%]]*)%]%(([^)]+)%)", '<a href="%2">%1</a>')
    -- **bold** / __bold__
    s = s:gsub("%*%*([^%*]+)%*%*", "<strong>%1</strong>")
    s = s:gsub("__([^_]+)__", "<strong>%1</strong>")
    -- *italic* / _italic_
    s = s:gsub("%*([^%*]+)%*", "<em>%1</em>")
    s = s:gsub("_([^_]+)_", "<em>%1</em>")
    -- ~~strikethrough~~
    s = s:gsub("~~([^~]+)~~", "<del>%1</del>")
    -- `inline code`
    s = s:gsub("`([^`]+)`", "<code>%1</code>")
    return s
end

local function is_header(line)
    return line:match("^(#+)%s+(.+)$")
end

local function is_hr(line)
    return line:match("^[-*_ ]+$") and line:match("^[-*_]") and not line:match("^%s*$")
end

local function is_code_fence(line)
    return line:match("^```")
end

local function is_bullet(line)
    return line:match("^%s*[-*]%s+")
end

local function is_table_row(line)
    return line:match("^%s*|") and line:match("|%s*$")
end

local function is_table_separator(line)
    return line:match("^%s*|%s*[-:]") and line:match("[-]%s*|%s*$")
end

local function render_table(rows)
    local html = {"<table>\n"}
    -- First non-separator row is thead
    local header_done = false
    for _, row in ipairs(rows) do
        if is_table_separator(row) then
            html[#html+1] = "</thead>\n<tbody>\n"
            header_done = true
        else
            local cells = {}
            -- Split on | (but not escaped)
            local raw = row:match("^%s*|%s*(.-)%s*|%s*$")
            if raw then
                for cell in raw:gmatch("([^|]+)") do
                    local c = cell:match("^%s*(.-)%s*$")
                    table.insert(cells, inline(c))
                end
            end
            if not header_done then
                html[#html+1] = "<tr>"
                for _, c in ipairs(cells) do
                    html[#html+1] = "<th>" .. c .. "</th>"
                end
                html[#html+1] = "</tr>\n"
            else
                html[#html+1] = "<tr>"
                for _, c in ipairs(cells) do
                    html[#html+1] = "<td>" .. c .. "</td>"
                end
                html[#html+1] = "</tr>\n"
            end
        end
    end
    if header_done then
        html[#html+1] = "</tbody>\n"
    else
        html[#html+1] = "</thead>\n"
    end
    html[#html+1] = "</table>\n"
    return table.concat(html)
end

local function render(content)
    local html = {
        '<!DOCTYPE html>',
        '<html lang="en">',
        '<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
        '<link rel="icon" type="image/svg+xml" href="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAzMiAzMiI+CiAgPHJlY3Qgd2lkdGg9IjMyIiBoZWlnaHQ9IjMyIiByeD0iNiIgZmlsbD0iIzBkMTExNyIvPgogIDxwYXRoIGQ9Ik04IDZoMTBsNiA2djE2YTIgMiAwIDAgMS0yIDJIOGEyIDIgMCAwIDEtMi0yVjhhMiAyIDAgMCAxIDItMnoiIGZpbGw9IiMxNjFiMjIiIHN0cm9rZT0iIzMwMzYzZCIgc3Ryb2tlLXdpZHRoPSIxLjUiLz4KICA8cGF0aCBkPSJNMTggNnY2aDYiIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzMwMzYzZCIgc3Ryb2tlLXdpZHRoPSIxLjUiLz4KICA8cmVjdCB4PSIxMCIgeT0iMTUiIHdpZHRoPSIxMiIgaGVpZ2h0PSIxLjUiIHJ4PSIwLjc1IiBmaWxsPSIjNThhNmZmIi8+CiAgPHJlY3QgeD0iMTAiIHk9IjE5IiB3aWR0aD0iMTAiIGhlaWdodD0iMS41IiByeD0iMC43NSIgZmlsbD0iIzhiOTQ5ZSIvPgogIDxyZWN0IHg9IjEwIiB5PSIyMyIgd2lkdGg9IjgiIGhlaWdodD0iMS41IiByeD0iMC43NSIgZmlsbD0iIzhiOTQ5ZSIvPgo8L3N2Zz4K">',
        '<title>',
    }

    local lines = {}
    for line in content:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
    end

    local i = 1
    local in_code = false
    local code_buf = {}
    local in_list = false
    local list_buf = {}
    local in_table = false
    local table_rows = {}
    local body = {}

    while i <= #lines do
        local line = lines[i]
        local trimmed = line:match("^%s*(.-)%s*$")

        -- Code fence
        if is_code_fence(trimmed) then
            if in_code then
                table.insert(body, "<pre><code>" .. escape(table.concat(code_buf, "\n")) .. "</code></pre>\n")
                code_buf = {}
                in_code = false
            else
                -- Close any open list
                if in_list then
                    table.insert(body, "<ul>\n" .. table.concat(list_buf) .. "</ul>\n")
                    list_buf = {}
                    in_list = false
                end
                in_code = true
            end
            i = i + 1
            goto continue
        end

        if in_code then
            table.insert(code_buf, line)
            i = i + 1
            goto continue
        end

        -- Flush table if current line breaks it
        if in_table and not is_table_row(trimmed) then
            table.insert(body, render_table(table_rows))
            table_rows = {}
            in_table = false
        end

        -- Extract title from first h1
        local _, _, h_level, h_text = line:find("^(#+)%s+(.+)$")
        if h_level and #h_level == 1 and #html == 5 then
            table.insert(html, escape(h_text) .. "</title>")
            table.insert(html, '<style>body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;max-width:900px;margin:0 auto;padding:20px;line-height:1.6;color:#e6edf3;background:#0d1117}a{color:#58a6ff}pre{background:#161b22;padding:16px;border-radius:6px;overflow-x:auto}code{background:#161b22;padding:2px 6px;border-radius:3px;font-size:0.9em}pre code{background:none;padding:0}table{border-collapse:collapse;width:100%}td,th{border:1px solid #30363d;padding:8px}th{background:#161b22}img{max-width:100%}</style>')
            table.insert(html, '</head><body>')
        end

        -- Empty line → paragraph break, close any open list or table
        if trimmed == "" then
            if in_list then
                table.insert(body, "<ul>\n" .. table.concat(list_buf) .. "</ul>\n")
                list_buf = {}
                in_list = false
            end
            if in_table then
                table.insert(body, render_table(table_rows))
                table_rows = {}
                in_table = false
            end
            i = i + 1
            goto continue
        end

        -- Horizontal rule
        if is_hr(trimmed) then
            if in_list then
                table.insert(body, "<ul>\n" .. table.concat(list_buf) .. "</ul>\n")
                list_buf = {}
                in_list = false
            end
            table.insert(body, "<hr>\n")
            i = i + 1
            goto continue
        end

        -- Headers
        if h_level then
            if in_list then
                table.insert(body, "<ul>\n" .. table.concat(list_buf) .. "</ul>\n")
                list_buf = {}
                in_list = false
            end
            local tag = "h" .. math.min(#h_level, 6)
            table.insert(body, "<" .. tag .. ">" .. inline(h_text) .. "</" .. tag .. ">\n")
            i = i + 1
            goto continue
        end

        -- Bullet list
        if is_bullet(trimmed) then
            local item = trimmed:match("^%s*[-*]%s+(.+)$")
            table.insert(list_buf, "<li>" .. inline(item) .. "</li>\n")
            in_list = true
            i = i + 1
            goto continue
        end

        -- Close list on non-bullet
        if in_list then
            table.insert(body, "<ul>\n" .. table.concat(list_buf) .. "</ul>\n")
            list_buf = {}
            in_list = false
        end

        -- Table row
        if is_table_row(trimmed) then
            table.insert(table_rows, trimmed)
            in_table = true
            i = i + 1
            goto continue
        end

        -- Flush table if not a table row anymore
        if in_table then
            table.insert(body, render_table(table_rows))
            table_rows = {}
            in_table = false
        end

        -- Regular paragraph line
        table.insert(body, "<p>" .. inline(trimmed) .. "</p>\n")
        i = i + 1

        ::continue::
    end

    -- Close any open code block
    if in_code then
        table.insert(body, "<pre><code>" .. escape(table.concat(code_buf, "\n")) .. "</code></pre>\n")
    end

    -- Close any open list
    if in_list then
        table.insert(body, "<ul>\n" .. table.concat(list_buf) .. "</ul>\n")
    end

    -- Close any open table
    if in_table then
        table.insert(body, render_table(table_rows))
    end

    -- If no title was set, add default
    if #html == 5 then
        table.insert(html, "Markdown</title>")
        table.insert(html, '<style>body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;max-width:900px;margin:0 auto;padding:20px;line-height:1.6;color:#e6edf3;background:#0d1117}a{color:#58a6ff}pre{background:#161b22;padding:16px;border-radius:6px;overflow-x:auto}code{background:#161b22;padding:2px 6px;border-radius:3px;font-size:0.9em}pre code{background:none;padding:0}table{border-collapse:collapse;width:100%}td,th{border:1px solid #30363d;padding:8px}th{background:#161b22}img{max-width:100%}</style>')
        table.insert(html, '</head><body>')
    end

    table.insert(html, table.concat(body))
    table.insert(html, '</body></html>')

    return table.concat(html, "\n")
end

-- Called by nginx
local filepath = ngx.var.request_uri
-- Remove query string
local qpos = filepath:find("?")
if qpos then filepath = filepath:sub(1, qpos - 1) end

local fullpath = "/mnt/host" .. filepath
local f, err = io.open(fullpath, "r")
if not f then
    ngx.status = 404
    ngx.say("<h1>404 Not Found</h1><p>" .. escape(fullpath) .. "</p>")
    return
end

local content = f:read("*a")
f:close()

ngx.header["Content-Type"] = "text/html; charset=utf-8"
ngx.say(render(content))
