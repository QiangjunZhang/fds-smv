..\..\..\..\..\FDS_Compilation\intel_win_64\fds_win_64 simple_panel_hot.fds 
ansys150 -b nolist -j simple_panel_hot_ansys -i read_geometry_hot.ans -o simple_panel_hot_ansys 
..\..\intel_win_64\fds2ftmi_win_64 simple_panel_hot 0.05 2 0 600 2 0 simple_panel_hot_to_ansys 
ansys150 -b nolist -j simple_panel_hot_ansys -i run_simple_panel_hot.ans -o simple_panel_hot_ansys  
ansys150 -b nolist -j simple_panel_hot_ansys -i plot_hot.ans -o simple_panel_hot_ansys  
set DISPLAY=localhost:0.0 
displayw -d POSTSCRIPT -j simple_panel_hot_ansys 
epstopdf --outfile=simple_panel_hot_ansys.pdf pscr000.eps  
move simple_panel_hot_ansys.pdf ..\..\scripts\SCRIPT_FIGURES\simple_panel_hot_ansys.pdf 
del *.loc 
del *.dat 
del *_ansys* 
del *.tmp 
del *.eps 