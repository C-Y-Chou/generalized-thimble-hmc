set terminal pngcairo size 1200,650 enhanced font 'Arial,12'
set output 'combined_distance_trace.png'
set datafile commentschars '#'
set grid
set key top right
set xlabel 'cycle prefix / mean samples per seed for all-available marker'
set ylabel 'combined four-z distance'
set style line 1 lc rgb '#1f77b4' lw 2 pt 7 ps 0.8
set style line 2 lc rgb '#d62728' lw 2 pt 7 ps 0.8
set style line 3 lc rgb '#1f77b4' lw 0 pt 9 ps 1.5
set style line 4 lc rgb '#d62728' lw 0 pt 9 ps 1.5
plot 'distance_withfb_prefix.dat' using 1:2 with linespoints ls 1 title 'withfb RMS z', \
     'distance_nofb_prefix.dat' using 1:2 with linespoints ls 2 title 'nofb RMS z', \
     'distance_withfb_endpoint.dat' using 1:2 with points ls 3 title 'withfb all RMS z', \
     'distance_nofb_endpoint.dat' using 1:2 with points ls 4 title 'nofb all RMS z'
