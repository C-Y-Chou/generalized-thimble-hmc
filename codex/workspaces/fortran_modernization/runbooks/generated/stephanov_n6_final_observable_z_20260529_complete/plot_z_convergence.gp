set terminal pngcairo size 1400,900 enhanced font 'Arial,12'
set output '/lustre1/home/cychou/TLTM_postrun_analysis/stephanov_n6_final_observable_z_20260529_complete/z_convergence_curve.png'
set datafile commentschars '#'
set grid
set key top left
set xlabel 'cycle prefix / mean samples per seed for all-available marker'
set ylabel 'z'
set multiplot layout 2,2 title 'Stephanov n=6 TLTM four-z convergence'
set style line 1 lc rgb '#1f77b4' lw 2 pt 7 ps 1.0
set style line 2 lc rgb '#d62728' lw 2 pt 7 ps 1.0
set style line 3 lc rgb '#1f77b4' lw 0 pt 9 ps 1.5
set style line 4 lc rgb '#d62728' lw 0 pt 9 ps 1.5
plot 'withfb_prefix.dat' using 1:2 with lines ls 1 title 'withfb common prefix', \
     'nofb_prefix.dat' using 1:2 with lines ls 2 title 'nofb common prefix', \
     'withfb_endpoint.dat' using 1:2 with points ls 3 title 'withfb all available', \
     'nofb_endpoint.dat' using 1:2 with points ls 4 title 'nofb all available'
set title 'chiral Im z'
plot 'withfb_prefix.dat' using 1:3 with lines ls 1 title 'withfb common prefix', \
     'nofb_prefix.dat' using 1:3 with lines ls 2 title 'nofb common prefix', \
     'withfb_endpoint.dat' using 1:3 with points ls 3 title 'withfb all available', \
     'nofb_endpoint.dat' using 1:3 with points ls 4 title 'nofb all available'
set title 'density Re z'
plot 'withfb_prefix.dat' using 1:4 with lines ls 1 title 'withfb common prefix', \
     'nofb_prefix.dat' using 1:4 with lines ls 2 title 'nofb common prefix', \
     'withfb_endpoint.dat' using 1:4 with points ls 3 title 'withfb all available', \
     'nofb_endpoint.dat' using 1:4 with points ls 4 title 'nofb all available'
set title 'density Im z'
plot 'withfb_prefix.dat' using 1:5 with lines ls 1 title 'withfb common prefix', \
     'nofb_prefix.dat' using 1:5 with lines ls 2 title 'nofb common prefix', \
     'withfb_endpoint.dat' using 1:5 with points ls 3 title 'withfb all available', \
     'nofb_endpoint.dat' using 1:5 with points ls 4 title 'nofb all available'
unset multiplot
