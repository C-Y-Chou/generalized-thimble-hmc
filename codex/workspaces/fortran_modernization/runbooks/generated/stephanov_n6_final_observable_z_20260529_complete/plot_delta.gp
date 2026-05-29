set terminal pngcairo size 1500,950 enhanced font 'Arial,12'
set datafile commentschars '#'
set grid
set key outside right center
set xlabel 'cycle prefix / mean samples per seed for all-available marker'
set style line 1 lc rgb '#1f77b4' lw 2 pt 7 ps 0.7
set style line 2 lc rgb '#d62728' lw 2 pt 7 ps 0.7
set style line 3 lc rgb '#1f77b4' lw 0 pt 9 ps 1.4
set style line 4 lc rgb '#d62728' lw 0 pt 9 ps 1.4
set style line 5 lc rgb '#2ca02c' lw 2 pt 7 ps 0.7
set style line 6 lc rgb '#2ca02c' lw 0 pt 9 ps 1.4
set output 'paired_method_delta_trace.png'
set multiplot layout 2,2 title 'Paired method delta traces'
set title 'chiral Re'
plot 0 with lines lc rgb '#444444' dt 2 title 'zero', \
     'paired_delta_chiral_Re.dat' using 1:2:3 with yerrorlines ls 5 title 'withfb-nofb prefix', \
     'paired_delta_endpoint_chiral_Re.dat' using 1:2:3 with yerrorbars ls 6 title 'withfb all - nofb matched'

set title 'chiral Im'
plot 0 with lines lc rgb '#444444' dt 2 title 'zero', \
     'paired_delta_chiral_Im.dat' using 1:2:3 with yerrorlines ls 5 title 'withfb-nofb prefix', \
     'paired_delta_endpoint_chiral_Im.dat' using 1:2:3 with yerrorbars ls 6 title 'withfb all - nofb matched'

set title 'density Re'
plot 0 with lines lc rgb '#444444' dt 2 title 'zero', \
     'paired_delta_density_Re.dat' using 1:2:3 with yerrorlines ls 5 title 'withfb-nofb prefix', \
     'paired_delta_endpoint_density_Re.dat' using 1:2:3 with yerrorbars ls 6 title 'withfb all - nofb matched'

set title 'density Im'
plot 0 with lines lc rgb '#444444' dt 2 title 'zero', \
     'paired_delta_density_Im.dat' using 1:2:3 with yerrorlines ls 5 title 'withfb-nofb prefix', \
     'paired_delta_endpoint_density_Im.dat' using 1:2:3 with yerrorbars ls 6 title 'withfb all - nofb matched'
unset multiplot
