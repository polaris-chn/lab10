.PHONY: sim verdi clean

PROJECT = soc_lite

VCS =	vcs -R \
		-debug_acc+all \
		-sverilog \
		+v2k \
		-fsdb \
		+define+FSDB \
		-full64 \
		-timescale=1ns/1ns \
		-notice			\
		-LDFLAGS -Wl,--no-as-needed \
		+incdir+./../inc \

VERDI =	verdi -sv \
		-nologo \
		+incdir+./../inc \
		-play setting.tcl \
		-ssf ${PROJECT}.fsdb 

sim:
		${VCS}  -f ${PROJECT}.f

verdi:
		${VERDI} -f ${PROJECT}.f &

clean:
		rm -rf ./csrc ./DVEfiles *.daidir *.log simv* *.key *.vpd \
				verdi* novas* *.fsdb *.txt


