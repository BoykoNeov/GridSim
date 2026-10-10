#!/bin/bash
# usage: run_v.sh TAG  -> W:\temp\claude\gridsim-m9-step4\v-TAG.log
cmd //v:on //c "start /belownormal /b /wait julia --project=W:\Claude_projects\GridSim\docs\evidence\gridsim-m9\harness\testenv W:\temp\claude\gridsim-m9-step4\run_v.jl > W:\temp\claude\gridsim-m9-step4\v-$1.log 2>&1 & exit !errorlevel!"
echo "exit=$?"; grep -E "Test Summary|^m9v|Fail|Error" /w/temp/claude/gridsim-m9-step4/v-$1.log | head -20
