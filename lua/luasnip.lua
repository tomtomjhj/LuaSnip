local active_snippet = nil
local ns_id = vim.api.nvim_create_namespace("luasnip")

local function get_active_snip() return active_snippet end

local function copy(args) return {args[1][1]} end

local snippets = {
	{
		trigger = "fn",
		nodes = {
			{
				type = 0,
				static_text = {"function "},
			},
			{
				type = 1,
				static_text = {""},
				pos = 1,
			},
			{
				type = 0,
				static_text = {"("},
			},
			{
				type = 1,
				static_text = {"lel"},
				pos = 2,
			},
			{
				type = 0,
				static_text = {")"}
			},
			{
				type = 2,
				fn = copy,
				args = {2},
				static_text = {""}
			},
			{
				type = 0,
				static_text = {" {","\t"},
			},
			{
				type = 1,
				static_text = {""},
				pos = 0,
			},
			{
				type = 0,
				static_text = {"", "}"}
			},
		},
		insert_nodes = {},
		current_insert = 0,
		parent = nil
	}
}

local function get_cursor_0ind()
	local c = vim.api.nvim_win_get_cursor(0)
	c[1] = c[1] - 1
	return c
end

local function set_cursor_0ind(c)
	c[1] = c[1] + 1
	vim.api.nvim_win_set_cursor(0, c)
end

-- returns snippet-object where its trigger matches the end of the line, nil if no match.
local function match_snippet(line)
	for i = 1, #snippets do
		local snip = snippets[i]
		-- if line ends with trigger
		if string.sub(line, #line - #snip.trigger + 1, #line) == snip.trigger then
			return vim.deepcopy(snip)
		end
	end
	return nil
end

local function has_static_text(node)
	return not (node.static_text[1] == "" and #node.static_text == 1)
end

local function move_to_mark(id)
	local new_cur_pos
	new_cur_pos = vim.api.nvim_buf_get_extmark_by_id(
		0, ns_id, id, {details = false})
	set_cursor_0ind(new_cur_pos)
end

local function set_from_rgrav(node, val)
	local pos = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, node.from, {})
	node.from = vim.api.nvim_buf_set_extmark(0, ns_id, pos[1], pos[2], {right_gravity = val})
end

local function set_to_rgrav(node, val)
	local pos = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, node.to, {})
	node.to = vim.api.nvim_buf_set_extmark(0, ns_id, pos[1], pos[2], {right_gravity = val})
end

local function enter_node(snip, node_id)
	for i = 1, node_id-1, 1 do
		set_from_rgrav(snip.nodes[i], false)
		set_to_rgrav(snip.nodes[i], false)
	end
	set_from_rgrav(snip.nodes[node_id], false)
	set_to_rgrav(snip.nodes[node_id], true)
	for i = node_id+1, #snip.nodes, 1 do
		set_from_rgrav(snip.nodes[i], true)
		set_to_rgrav(snip.nodes[i], true)
	end
end

-- returns text in a node, eg. {"from_line1", "line2", to_line3}
local function get_text(node)
	local node_from = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, node.from, {})
	local node_to = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, node.to, {})

	-- end-exclusive indexing.
	local lines = vim.api.nvim_buf_get_lines(0, node_from[1], node_to[1]+1, false)

	if #lines == 1 then
		lines[1] = string.sub(lines[1], node_from[2]+1, node_to[2])
	else
		lines[1] = string.sub(lines[1], node_from[2]+1, #lines[1])

		-- node-range is end-exclusive.
		lines[#lines] = string.sub(lines[#lines], 1, node_to[2])
	end
	return lines
end

local function set_text(snip, node, text)
	local node_from = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, node.from, {})
	local node_to = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, node.to, {})

	enter_node(snip, node.indx)
	vim.api.nvim_buf_set_text(0, node_from[1], node_from[2], node_to[1], node_to[2], text)
end

local function exit_snip()
	for _, node in ipairs(active_snippet.nodes) do
		vim.api.nvim_buf_del_extmark(0, ns_id, node.from)
		vim.api.nvim_buf_del_extmark(0, ns_id, node.to)
	end
	active_snippet = active_snippet.parent
end

local function make_args(snip, arglist)
	local args = {}
	for i, ins_id in ipairs(arglist) do
		args[i] = get_text(snip.insert_nodes[ins_id])
	end
	return args
end

local function update_fn_text(snip, node)
	set_text(snip, node, node.fn(make_args(snip, node.args)))
end

-- jump(-1) on first insert would jump to end of snippet (0-insert).
local function jump(direction)
	local snip = active_snippet
	if snip == nil then
		return false
	end
	-- update text in dependents on leaving node.
	for _, node in ipairs(snip.insert_nodes[snip.current_insert].dependents) do
		update_fn_text(snip, node)
	end
	local tmp = snip.current_insert + direction
	-- Would jump to invalid node?
	if snip.insert_nodes[tmp] == nil then
		snip.current_insert = 0
	else
		snip.current_insert = tmp
	end

	enter_node(snip, snip.insert_nodes[snip.current_insert].indx)

	move_to_mark(snip.insert_nodes[snip.current_insert].from)
	if snip.current_insert == 0 then
		exit_snip()
	end
	return true
end

-- delete n chars before cursor, MOVES CURSOR
local function remove_n_before_cur(n)
	local cur = get_cursor_0ind()
	vim.api.nvim_buf_set_text(0, cur[1], cur[2]-n, cur[1], cur[2], {""})
	cur[2] = cur[2]-n
	set_cursor_0ind(cur)
end

local function dump_active()
	for i, node in ipairs(active_snippet.nodes) do
		print(i)
		local c = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, node.from, {details = false})
		print(c[1], c[2])
		c = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, node.to, {details = false})
		print(c[1], c[2])
	end
end

local function expand(snip)
	snip.parent = active_snippet
	active_snippet = snip

	-- remove snippet-trigger, Cursor at start of future snippet text.
	local triglen = #snip.trigger;
	remove_n_before_cur(triglen)


	-- i needed for functions.
	for i, node in ipairs(snip.nodes) do
		-- save cursor position for later.
		local cur = get_cursor_0ind()

		-- place extmark directly on previously saved position (first char
		-- of inserted text) after putting text.
		node.from = vim.api.nvim_buf_set_extmark(0, ns_id, cur[1], cur[2], {right_gravity = false})

		if has_static_text(node) then
			-- leaves cursor behind last char of inserted text.
			vim.api.nvim_put(node.static_text, "c", false, true);
		end

		cur = get_cursor_0ind()
		-- place extmark directly behind last char of put text.
		node.to = vim.api.nvim_buf_set_extmark(0, ns_id, cur[1], cur[2], {right_gravity = false})

		if node.type == 1 then
			snip.insert_nodes[node.pos] = node
			-- do here as long as snippets need to be defined manually
			node.dependents = {}
		end
		-- do here as long as snippets need to be defined manually
		node.indx = i
	end

	for _, node in ipairs(snip.nodes) do
		if node.type == 2 then
			update_fn_text(snip, node)
			-- append node to dependents-table of args.
			for _, arg in ipairs(node.args) do
				snip.insert_nodes[arg].dependents[#snip.insert_nodes[arg].dependents+1] = node
			end
		end
	end

	-- Jump to first insert.
	jump(1);
end

-- returns current line with text up-to and excluding the cursor.
local function get_current_line_to_cursor()
	local cur = get_cursor_0ind()
	-- cur-rows are 1-indexed, api-rows 0.
	local line = vim.api.nvim_buf_get_lines(0, cur[1], cur[1]+1, false)
	return string.sub(line[1], 1, cur[2])
end

local function indent(snip, line)
	local prefix = string.match(line, '^%s*')
	for _, node in ipairs(snip.nodes) do
		-- put prefix behind newlines.
		for i = 2, #node.static_text do
			node.static_text[i] = prefix .. node.static_text[i]
		end
	end
end

-- return true and expand snippet if expandable, return false if not.
local function expand_or_jump()
	local line = get_current_line_to_cursor()
	local snip = match_snippet(line)
	if snip ~= nil then
		indent(snip, line)
		expand(snip)
		return true
	end
	if active_snippet ~= nil then
		jump(1)
		return true
	end
	return false
end

return {
	expand_or_jump = expand_or_jump,
	jump = jump,
	snippets = snippets,
	get_active_snip = get_active_snip,
	dump_active = dump_active
}
