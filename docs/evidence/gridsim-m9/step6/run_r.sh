#!/bin/bash
# usage: run_r.sh TAG  -> W:\temp\claude\gridsim-m9-step6\r-TAG.log
cmd //v:on //c "start /belownormal /b /wait julia --project=W:\Claude_projects\GridSim\docs\evidence\gridsim-m9\harness\testenv W:\Claude_projects\GridSim\docs\evidence\gridsim-m9\step6\run_r.jl > W:\temp\claude\gridsim-m9-step6\r-$1.log 2>&1 & exit !errorlevel!"
echo "exit=$?"; grep -E "Test Summary|^m9r|Fail|Error" /w/temp/claude/gridsim-m9-step6/r-$1.log | head -30
