-- Copyright (c) 2020, The Pallene Developers
-- Pallene is licensed under the MIT license.
-- Please refer to the LICENSE and AUTHORS files for details
-- SPDX-License-Identifier: MIT

local util = require "pallene.util"

-- !!! IMPORTANT - READ THIS !!!
--
-- If you change the output of this translator, please run the `benchmarks/generate_lua` script
-- to update the ".lua" files of our benchmarks.

----------

-- This file implements a Pallene to Lua translator.
--
-- The Pallene compiler is divided into two logical ends:
-- * The frontend which parses Pallene source code to generate AST and performs semantic analysis.
-- * The backend which generates C source code.
--
-- Both these ends are decoupled, this provides us with the flexibility to integrate another backend
-- that generates Lua. The users can run the compiler with `--emit-lua` trigger the translator to
-- generate plain Lua instead of C.
--
-- The generation of Lua is performed by a different backend (implemented here). It accepts input
-- string and the AST generated by the parser. The generator then walks over the AST replacing
-- type annotations with white space. Interestingly spaces, newlines, comments and pretty much
-- everything else other than type annotations are retained in the translated code. Thus, the
-- formatting in the original input is preserved, which means the error messages always point to
-- the same location in both Pallene and Lua code.
--

local translator = {}

local Translator = util.Class()

function Translator:init(input)
    self.input = input -- string
    self.last_index = 1 -- integer
    self.partials = {} -- list of strings
    return self
end

function Translator:add_previous(stop_index)
    assert(self.last_index <= stop_index + 1)
    local partial = self.input:sub(self.last_index, stop_index)
    --partial = partial:gsub('local ', '')
    table.insert(self.partials, partial)
    self.last_index = stop_index + 1
end

function Translator:erase_region(start_index, stop_index)
    assert(self.last_index <= start_index)
    assert(start_index <= stop_index + 1)
    self:add_previous(start_index - 1)

    local region = self.input:sub(start_index, stop_index)
    local partial = region:gsub("[^\n\r]", "")
    table.insert(self.partials, partial)

    self.last_index = stop_index + 1
end


function translator.translate(input, prog_ast)
    local instance = Translator.new(input)

    -- Erase all type regions, while preserving comments
    -- As a sanity check, assert that the comment regions are either inside or outside the type
    -- regions, not crossing the boundaries.
    local j = 1
    local comments = prog_ast.comment_regions
    for _, region in ipairs(prog_ast.type_regions) do
        local start_index = region[1]
        local end_index   = region[2]

        -- Skip over the comments before the current region.
        while j <= #comments and comments[j][2] < start_index do
            j = j + 1
        end

        -- Preserve the comments inside the current region.
        while j <= #comments and comments[j][2] <= end_index do
            assert(start_index <= comments[j][1])
            instance:erase_region(start_index, comments[j][1] - 1)
            start_index = comments[j][2] + 1
            j = j + 1
        end

        -- Ensure that the next comment is outside the current region.
        if j <= #comments then
            assert(end_index < comments[j][1])
        end

        instance:erase_region(start_index, end_index)
    end

    -- Whatever characters that were not included in the partials should be added.
    instance:add_previous(#input)

    return table.concat(instance.partials)
end

return translator
