#!/bin/bash
# usage: run_d.sh TAG  -> W:\temp\claude\gridsim-m9-step5\d-TAG.log
cmd //v:on //c "start /belownormal /b /wait julia --project=W:\Claude_projects\GridSim\docs\evidence\gridsim-m9\harness\testenv W:\Claude_projects\GridSim\docs\evidence\gridsim-m9\step5\run_d.jl > W:\temp\claude\gridsim-m9-step5\d-$1.log 2>&1 & exit !errorlevel!"
echo "exit=$?"; grep -E "Test Summary|^m9d|Fail|Error" /w/temp/claude/gridsim-m9-step5/d-$1.log | head -30
