--!A cross-platform build utility based on Lua
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
-- 
-- Copyright (C) 2015-2020, TBOOX Open Source Group.
--
-- @author      ruki
-- @file        object.lua
--

-- imports
import("core.base.option")
import("core.project.rule")
import("core.project.config")
import("core.project.project")
import("private.async.runjobs")

-- add batch jobs for the custom rule
function _add_batchjobs_for_rule(batchjobs, rootjob, target, sourcebatch, suffix)

    -- get rule
    local rulename = assert(sourcebatch.rulename, "unknown rule for sourcebatch!")
    local ruleinst = assert(project.rule(rulename) or rule.rule(rulename), "unknown rule: %s", rulename)

    -- add batch jobs
    local scriptname = "build_files" .. (suffix and ("_" .. suffix) or "")
    local script = ruleinst:script(scriptname)
    if script then
        if ruleinst:extraconf(scriptname, "batch") then
            assert(script(target, batchjobs, sourcebatch, {rootjob = rootjob}), "rule(%s):%s(): no returned job!", rulename, scriptname)
        else
            batchjobs:addjob("rule/" .. rulename .. "/" .. scriptname, function (index, total)
                script(target, sourcebatch, {progress = (index * 100) / total})
            end, rootjob)
        end
    else
        scriptname = "build_file" .. (suffix and ("_" .. suffix) or "")
        script = ruleinst:script(scriptname)
        if script then
            local sourcekind = sourcebatch.sourcekind
            local jobname = "rule/" .. rulename .. "/" .. scriptname .. "/"
            for idx, sourcefile in ipairs(sourcebatch.sourcefiles) do
                batchjobs:addjob(jobname .. idx, function (index, total)
                    script(target, sourcefile, {sourcekind = sourcekind, progress = (index * 100) / total})
                end, rootjob)
            end
        end
    end
end

-- add batch jobs for target
function _add_batchjobs_for_target(batchjobs, rootjob, target, sourcebatch, suffix)

    -- add batch jobs
    local scriptname = "build_files" .. (suffix and ("_" .. suffix) or "")
    local script = target:script(scriptname)
    if script then
        if target:extraconf(scriptname, "batch") then
            assert(script(target, batchjobs, sourcebatch, {rootjob = rootjob}), "target(%s):%s(): no returned job!", target:name(), scriptname)
        else
            batchjobs:addjob(target:name() .. "/" .. scriptname, function (index, total)
                script(target, sourcebatch, {progress = (index * 100) / total})
            end, rootjob)
        end
        return true
    else
        scriptname = "build_file" .. (suffix and ("_" .. suffix) or "")
        script = target:script(scriptname)
        if script then
            local sourcekind = sourcebatch.sourcekind
            local jobname = target:name() .. "/" .. scriptname .. "/"
            for idx, sourcefile in ipairs(sourcebatch.sourcefiles) do
                batchjobs:addjob(jobname .. idx, function (index, total)
                    script(target, sourcefile, {sourcekind = sourcekind, progress = (index * 100) / total})
                end, rootjob)
            end
            return true
        end
    end
end

-- add batch jobs for building source files
function add_batchjobs_for_sourcefiles(batchjobs, rootjob, target, sourcebatches)

    -- add batch jobs for build_after
    local job_build_after = batchjobs:newgroup(target:name() .. "/after_build_files")
    for _, sourcebatch in pairs(sourcebatches) do
        _add_batchjobs_for_rule(batchjobs, job_build_after, target, sourcebatch, "after")
        _add_batchjobs_for_target(batchjobs, job_build_after, target, sourcebatch, "after")
    end
    if batchjobs:depsize(job_build_after) > 0 then
        batchjobs:add(job_build_after, rootjob)
    else
        job_build_after = rootjob
    end

    -- add source batches
    local job_build = batchjobs:newgroup(target:name() .. "/build_files")
    for _, sourcebatch in pairs(sourcebatches) do
        if not _add_batchjobs_for_target(target, job_build, target, sourcebatch) then
            _add_batchjobs_for_rule(batchjobs, job_build, target, sourcebatch)
        end
    end
    if batchjobs:depsize(job_build) > 0 then
        batchjobs:add(job_build, job_build_after)
    else
        job_build = job_build_after
    end

    -- add source batches with custom rules before building other sources
    local job_build_before = batchjobs:newgroup(target:name() .. "/before_build_files")
    for _, sourcebatch in pairs(sourcebatches) do
        _add_batchjobs_for_rule(batchjobs, job_build_before, target, sourcebatch, "before")
        _add_batchjobs_for_target(batchjobs, job_build_before, target, sourcebatch, "before")
    end
    if batchjobs:depsize(job_build_before) > 0 then
        batchjobs:add(job_build_before, job_build)
    else
        job_build_before = job_build
    end
    return job_build_before
end

-- add batch jobs for building object files
function main(batchjobs, rootjob, target)
    return add_batchjobs_for_sourcefiles(batchjobs, rootjob, target, target:sourcebatches())
end

