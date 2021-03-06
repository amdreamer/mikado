import sys
import os,sys                                                              
import glob
import itertools
import subprocess
import yaml
from os import listdir
from os.path import isfile, join
from shutil import which
 

CFG=workflow.overwrite_configfile

# Get shortcuts from configuration file
	

# Short read fields
R1 = []
R2 = []
SAMPLES = []
STRANDEDNESS = []
if "short_reads" in config:
	R1 = config["short_reads"]["r1"]
	R2 = config["short_reads"]["r2"]
	SAMPLES = config["short_reads"]["samples"]
	STRANDEDNESS = config["short_reads"]["strandedness"]

# Long read fields
L_FILES = []
L_SAMPLES = []
L_STRANDEDNESS = []
if "long_reads" in config:
	L_FILES = config["long_reads"]["files"]
	L_SAMPLES = config["long_reads"]["samples"]
	L_STRANDEDNESS = config["long_reads"]["strandedness"]

# Required reference fields
REF = config["reference"]["genome"]
MIN_INTRON = config["reference"]["min_intron"]
MAX_INTRON = config["reference"]["max_intron"]

# Optional reference fields
REF_TRANS = ""
if "transcriptome" in config["reference"]:
	REF_TRANS = config["reference"]["transcriptome"]


NAME = config["name"]
OUT_DIR = config["out_dir"]
if "threads" in config:
    THREADS = int(config["threads"])
else:
    THREADS = 1
# THREADS = int(config["threads"])
TGG_MAX_MEM = config["tgg_max_mem"]

# List of alignment and assembly methods to test
ALIGNMENT_METHODS = config["align_methods"]
L_ALIGNMENT_METHODS = []
if "long_read_align_methods" in config:
	L_ALIGNMENT_METHODS = config["long_read_align_methods"]
ASSEMBLY_METHODS = config["asm_methods"]


# Directory shortcuts
OUT_DIR_FULL = os.path.abspath(OUT_DIR)
READS_DIR = OUT_DIR + "/1-reads"
READS_DIR_FULL = os.path.abspath(READS_DIR)
ALIGN_DIR = OUT_DIR + "/2-alignments"
ALIGN_DIR_FULL = os.path.abspath(ALIGN_DIR)
ASM_DIR = OUT_DIR + "/3-assemblies"
ASM_DIR_FULL = os.path.abspath(ASM_DIR)
PORTCULLIS_DIR = OUT_DIR + "/4-portcullis"
PORTCULLIS_DIR_FULL = os.path.abspath(PORTCULLIS_DIR)

CWD = os.getcwd()
ALIGN_COLLECT = which("align_collect.py")
ASM_COLLECT = which("asm_collect.py")
CLASS = which("class_run.py")



SAMPLE_MAP = {}
INPUT_1_MAP = {}
INPUT_2_MAP = {}
EXT_MAP = {}
for i in range(len(SAMPLES)):
	SAMPLE_MAP[SAMPLES[i]] = STRANDEDNESS[i].lower()
	name, ext = os.path.splitext(R1[i])
	r1 = READS_DIR+"/"+SAMPLES[i]+".R1.fq"
	r2 = READS_DIR+"/"+SAMPLES[i]+".R2.fq" if R2[i] else ""
	if ext == ".gz" or ext == ".bz2":
		r1 += ext
		r2 += ext if R2[i] else ""
	EXT_MAP[SAMPLES[i]] = ext
	INPUT_1_MAP[SAMPLES[i]] = r1
	INPUT_2_MAP[SAMPLES[i]] = r2

L_SAMPLE_MAP = {}
L_INPUT_MAP = {}
L_EXT_MAP = {}
for i in range(len(L_SAMPLES)):
	L_SAMPLE_MAP[L_SAMPLES[i]] = L_STRANDEDNESS[i].lower()
	ext = L_FILES[i].split(sep=".")[-1]
	lr = ""
	if ext in ("fasta", "fa", "fna"):
		lr = READS_DIR+"/"+L_SAMPLES[i]+".long.fa"
	elif ext in ("fastq", "fq"):
		lr = READS_DIR+"/"+L_SAMPLES[i]+".long.fq"
	else:
		exit(1)
	L_EXT_MAP[L_SAMPLES[i]] = ext
	L_INPUT_MAP[L_SAMPLES[i]] = lr


ALIGN_RUNS = []
for aln in ALIGNMENT_METHODS:
	for samp in SAMPLES:
		for index, setting in enumerate(ALIGNMENT_METHODS[aln]):
			ALIGN_RUNS.append(aln+"-"+samp+"-"+str(index))

L_ALIGN_RUNS = []
for aln in L_ALIGNMENT_METHODS:
	for samp in L_SAMPLES:
		for index, setting in enumerate(L_ALIGNMENT_METHODS[aln]):
			L_ALIGN_RUNS.append(aln+"-"+samp+"-"+str(index))

def makeAlignRunArray(aligner):
	RUNS = []
	if aligner in ALIGNMENT_METHODS:
	        for index, setting in enumerate(ALIGNMENT_METHODS[aligner]):
        	        RUNS.append(index)
	return RUNS

def makeLAlignRunArray(aligner):
	RUNS = []
	if aligner in L_ALIGNMENT_METHODS:
	        for index, setting in enumerate(L_ALIGNMENT_METHODS[aligner]):
        	        RUNS.append(index)
	return RUNS

TOPHAT_RUNS = makeAlignRunArray("tophat")
GSNAP_RUNS = makeAlignRunArray("gsnap")
STAR_RUNS = makeAlignRunArray("star")
HISAT_RUNS = makeAlignRunArray("hisat")

LR_GMAP_RUNS = makeLAlignRunArray("gmap")
LR_STAR_RUNS = makeLAlignRunArray("star")

def makeAsmRunArray(assembler):
	RUNS = []
	if assembler in ASSEMBLY_METHODS:
	        for index, setting in enumerate(ASSEMBLY_METHODS[assembler]):
        	        RUNS.append(index)
	return RUNS


CUFFLINKS_RUNS = makeAsmRunArray("cufflinks")
TRINITY_RUNS = makeAsmRunArray("trinity")
STRINGTIE_RUNS = makeAsmRunArray("stringtie")
CLASS_RUNS = makeAsmRunArray("class")

SAMPLE_STR = ",".join(SAMPLES)

RUN_PORTCULLIS = config["portcullis"]["do"]
CANONICAL_JUNCS = config["portcullis"]["canonical_juncs"]

PORTCULLIS_IN = {}
for a in ALIGN_RUNS :
	PORTCULLIS_IN[a] = ALIGN_DIR+"/output/" + a + ".sorted.bam"

aln_abrv = {"tophat":"tph", "star":"sta", "gsnap":"gsp", "hisat":"hst", "gmap":"gmp"}
asm_abrv = {"cufflinks":"cuf", "stringtie":"stn", "class":"cls", "trinity":"trn"}
	
GTF_ASSEMBLY_METHODS = []
GFF_ASSEMBLY_METHODS = []
for asm in ASSEMBLY_METHODS:
	if asm == "cufflinks" or asm == "stringtie" or asm == "class":
		GTF_ASSEMBLY_METHODS.append(asm)
	elif asm == "trinity":
		GFF_ASSEMBLY_METHODS.append(asm)

TRANSCRIPT_ARRAY=[]
LABEL_ARRAY=[]
SS_ARRAY=[]
for samp in SAMPLES:
	for aln in ALIGNMENT_METHODS:
		for aln_idx, setting in enumerate(ALIGNMENT_METHODS[aln]):
			samp_idx = "-" + samp + "-" + str(aln_idx)
			aln_str = aln + samp_idx
			abv_aln_str = aln_abrv[aln] + samp_idx
			for gtf in GTF_ASSEMBLY_METHODS:
				for index, setting in enumerate(ASSEMBLY_METHODS[gtf]):
					filename = gtf + "-" + str(index) + "-" + aln_str + ".gtf"
					TRANSCRIPT_ARRAY.append(ASM_DIR + "/output/" + filename)
					LABEL_ARRAY.append(asm_abrv[gtf] + "-" + str(index) + "-" + abv_aln_str)
					if not SAMPLE_MAP[samp] == "fr-unstranded":
						SS_ARRAY.append(TRANSCRIPT_ARRAY[-1])
			for gff in GFF_ASSEMBLY_METHODS:
				for index, setting in enumerate(ASSEMBLY_METHODS[gff]):
					filename = gff + "-" + str(index) + "-" + aln_str + ".gff"
					TRANSCRIPT_ARRAY.append(ASM_DIR + "/output/" + filename)
					LABEL_ARRAY.append(asm_abrv[gff] + "-" + str(index) + "-" + abv_aln_str)
					if not SAMPLE_MAP[samp] == "fr-unstranded":
						SS_ARRAY.append(TRANSCRIPT_ARRAY[-1])

TRANSCRIPTS_STR = ",".join(TRANSCRIPT_ARRAY)
LABEL_STR = ",".join(LABEL_ARRAY)
SS_STR = ",".join(SS_ARRAY)


LR_ARRAY=[]
LR_LABEL_ARRAY=[]
LR_SS_ARRAY=[]
for samp in L_SAMPLES:
	for aln in L_ALIGNMENT_METHODS:
		for aln_idx, setting in enumerate(L_ALIGNMENT_METHODS[aln]):
			samp_idx = "-" + samp + "-" + str(aln_idx)
			aln_str = "lr_" + aln + samp_idx
			abv_aln_str = "lr_" + aln_abrv[aln] + samp_idx
			filename = aln_str + (".gff" if aln == "gmap" else ".gtf")
			LR_ARRAY.append(ALIGN_DIR + "/lr_output/" + filename)
			LR_LABEL_ARRAY.append(abv_aln_str)
			if not L_SAMPLE_MAP[samp] == "u":
				LR_SS_ARRAY.append(TRANSCRIPT_ARRAY[-1])

LR_STR = ",".join(LR_ARRAY)
LR_LABEL_STR = ",".join(LR_LABEL_ARRAY)
LR_SS_STR = ",".join(LR_SS_ARRAY)

MIKADO_IN_STR = ",".join([TRANSCRIPTS_STR,LR_STR])
MIKADO_LABEL_STR = ",".join([LABEL_STR,LR_LABEL_STR])
MIKADO_SS_STR = ",".join(filter(None, [SS_STR,LR_SS_STR]))

def seSample(sample):
	s = SAMPLE_MAP[sample]
	if (s == "f" or s == "r"):
		if not INPUT_2_MAP[sample]:
			return True
		else:
			i=0
			# Should throw an error here
	return False		
			
			
def tophatInput(sample):
        if not seSample(sample):
                return INPUT_1_MAP[sample] + " " + INPUT_2_MAP[sample]
        else:
                return INPUT_1_MAP[sample]

# This also works for cufflinks
def tophatStrandOption(sample):
	if SAMPLE_MAP[sample] == "f":
		return "--library-type=fr-secondstrand"
	elif SAMPLE_MAP[sample] == "r":
		return "--library-type=fr-firststrand"
	else:
		return "--library-type=" + SAMPLE_MAP[sample]

def starCompressionOption(sample):
	if EXT_MAP[sample] == ".gz":
		return "--readFilesCommand zcat"
	elif EXT_MAP[sample] == ".bz":
		return "--readFilesCommand bzcat"
	else:
		return ""

def starInput(sample):
	if not seSample(sample):
		return "--readFilesIn " + os.path.abspath(INPUT_1_MAP[sample]) + " " + os.path.abspath(INPUT_2_MAP[sample])
	else:
		return "--readFilesIn " + os.path.abspath(INPUT_1_MAP[sample])

def starLongInput(sample):
	return "--readFilesIn " + os.path.abspath(L_INPUT_MAP[sample])

def hisatStrandOption(sample):
	if SAMPLE_MAP[sample] == "fr-firststrand":
		return "--rna-strandness=RF"
	elif SAMPLE_MAP[sample] == "fr-secondstrand":
		return "--rna-strandness=FR"
	elif SAMPLE_MAP[sample] == "f":
		return "--rna-strandness=F"
	elif SAMPLE_MAP[sample] == "r":
		return "--rna-strandness=R"
	else:
		return ""

def hisatInput(sample):
	if not seSample(sample):
		return "-1 " + INPUT_1_MAP[sample] + " -2 " + INPUT_2_MAP[sample]
	else:
		return "-U " + INPUT_1_MAP[sample]


def extractSample(align_run):
	parts = align_run.split("-")
	return parts[1]

def trinityStrandOption(sample):
	if SAMPLE_MAP[sample] == "fr-firststrand":
		return "--SS_lib_type=RF"
	elif SAMPLE_MAP[sample] == "fr-secondstrand":
		return "--SS_lib_type=FR"
	elif SAMPLE_MAP[sample] == "f":
		return "--SS_lib_type=F"
	elif SAMPLE_MAP[sample] == "r":
		return "--SS_lib_type=R"
	else:
		return ""

def portcullisStrandOption(run, command, step):
    parts=run.split("-")
    sample=parts[1]
    cmd = subprocess.Popen("{} portcullis {} --help".format(command, step),
	                       shell=True, stdout=subprocess.PIPE).stdout.read().decode()
    if not any("strandedness" in _ for _ in cmd.split("\n")):
        return ""
    else:
        if SAMPLE_MAP[sample] == "fr-firststrand":
            return "--strandedness=firststrand"
        elif SAMPLE_MAP[sample] == "fr-secondstrand":
            return "--strandedness=secondstrand"
        else:
            return "--strandedness=unstranded"

def loadPre(command):
        cc = command.strip()
        if not cc:
                return ""
        else:
                return "set +u && {} &&".format(cc)

def trinityInput(sample):
    if not seSample(sample):
        return "--left={} --right={}".format(INPUT_1_MAP[sample], INPUT_2_MAP[sample])
    else:
        return "--single={} ".format(INPUT_1_MAP[sample])

def trinityParameters(command, sample, REF, TGG_MAX_MEM):
    cmd = "set +u && {} && Trinity --version && set -u".format(command)
    output = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE).stdout.read().decode()
    version = [_ for _ in output.split("\n") if re.match("Trinity version:", _)][0]
    version = re.sub("Trinity version: [^_]*_(r|v)", "", version)
    if str(TGG_MAX_MEM).isdigit() is True:
        TGG_MAX_MEM = int(TGG_MAX_MEM)
        if TGG_MAX_MEM >= 1000:
            TGG_MAX_MEM = "{}G".format(int(TGG_MAX_MEM/1000))
    if version.startswith("201"):   # Old versions
        reads = trinityInput(sample)
        memory = "--JM={}".format(TGG_MAX_MEM)
        cmd = "{reads} --genome={ref} {memory} --genome_guided_use_bam".format(reads=reads, ref=REF, memory=memory)
    else:
        memory="--max_memory={}".format(TGG_MAX_MEM)
        cmd = "--full_cleanup {memory} --genome_guided_bam".format(memory=memory)
    return cmd

def gmap_intron_lengths(command, MAX_INTRON):
    cmd = "{} gmap --help".format(command)
    output = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.read().decode()
    if "--max-intronlength-middle" in output:
        return "--max-intronlength-middle={mi} --max-intronlength-ends={mi}".format(MAX_INTRON)
    else:
        return "--intronlength={}".format(MAX_INTRON)


#########################
Rules

localrules: mikado_cfg, tophat_all, gsnap_all, star_all, hisat_all, cufflinks_all, trinity_all, stringtie_all, class_all, lr_gmap_all, lr_star_all, clean, align_all, lreads_all, asm_all, all

rule all:
	input:
		mikado=OUT_DIR + "/mikado.yaml",
		align=ALIGN_DIR+"/alignment.stats",
		#l_align=ALIGN_DIR+"/lr_alignment.stats",
		asm=ASM_DIR+"/assembly.stats"

rule clean:
	shell: "rm -rf {OUT_DIR}"


rule align_tophat_index:
	input: ref=REF
	output: ALIGN_DIR + "/tophat/index/" + NAME + ".4.bt2"
	params: 
		idxdir=ALIGN_DIR + "/tophat/index/" + NAME,
		load=loadPre(config["load"]["tophat"])
	log: ALIGN_DIR + "/tophat.index.log"
	threads: 1
	message: "Indexing genome with tophat"
	shell: "{params.load} bowtie2-build {input.ref} {params.idxdir} > {log} 2>&1"


rule align_tophat:
	input:
		r1=lambda wildcards: INPUT_1_MAP[wildcards.sample],
		index=rules.align_tophat_index.output
	output:
		link=ALIGN_DIR+"/output/tophat-{sample}-{run,\d+}.bam"
	params: 
		outdir=ALIGN_DIR+"/tophat/{sample}-{run}",
		bam=ALIGN_DIR+"/tophat/{sample}-{run}/accepted_hits.bam",
		indexdir=ALIGN_DIR+"/tophat/index/"+NAME,
		load=loadPre(config["load"]["tophat"]),
		extra=lambda wildcards: config["align_methods"]["tophat"][int(wildcards.run)],
		link_src="../tophat/{sample}-{run}/accepted_hits.bam",
		strand=lambda wildcards: tophatStrandOption(wildcards.sample),
		infiles=lambda wildcards: tophatInput(wildcards.sample),
		#trans="--GTF=" + REF_TRANS if REF_TRANS else ""
		trans=""
	log: ALIGN_DIR + "/tophat-{sample}-{run}.log"
	threads: THREADS
	message: "Aligning RNAseq data with tophat (sample - {wildcards.sample} - run {wildcards.run})"
	shell: "{params.load} tophat2 --output-dir={params.outdir} --no-sort-bam --num-threads={threads} --min-intron-length={MIN_INTRON} --max-intron-length={MAX_INTRON} {params.strand} {params.trans} {params.extra} {params.indexdir} {params.infiles} > {log} 2>&1 && ln -sf {params.link_src} {output.link} && touch -h {output.link}"

rule tophat_all:
	input: expand(ALIGN_DIR+"/output/tophat-{sample}-{run}.bam", sample=SAMPLES, run=TOPHAT_RUNS)
	output: ALIGN_DIR+"/tophat.done"
	shell: "touch {output}"	

rule align_gsnap_index:
	input: REF
	output: ALIGN_DIR + "/gsnap/index/" + NAME + "/" + NAME + ".sachildguide1024"
	params: load=loadPre(config["load"]["gmap"])
	log: ALIGN_DIR +"/gsnap.index.log"
	threads: 1
	message: "Indexing genome with gsnap"
	shell: "{params.load} gmap_build --dir={ALIGN_DIR}/gsnap/index --db={NAME} {input} > {log} 2>&1"


rule align_gsnap:
	input:
		r1=lambda wildcards: INPUT_1_MAP[wildcards.sample],
		index=rules.align_gsnap_index.output
	output:
		bam=ALIGN_DIR+"/gsnap/{sample}-{run,\d+}/gsnap.bam",
		link=ALIGN_DIR+"/output/gsnap-{sample}-{run,\d+}.bam"
	params: 
		load=loadPre(config["load"]["gmap"]),
		load_sam=loadPre(config["load"]["samtools"]),
		extra=lambda wildcards: config["align_methods"]["gsnap"][int(wildcards.run)],
		link_src="../gsnap/{sample}-{run}/gsnap.bam",
		infiles=lambda wildcards: tophatInput(wildcards.sample)	# Can use tophat function safely here
	log: ALIGN_DIR+"/gsnap-{sample}-{run}.log"
	threads: THREADS
	message: "Aligning RNAseq with gsnap (sample {wildcards.sample} - run {wildcards.run})"
	shell: "{params.load} {params.load_sam} gsnap --dir={ALIGN_DIR}/gsnap/index --db={NAME} {params.extra} --novelsplicing=1 --localsplicedist={MAX_INTRON} --nthreads={threads} --format=sam --npaths=20 {params.infiles} 2> {log} | samtools view -b -@ {threads} - > {output.bam} && ln -sf {params.link_src} {output.link} && touch -h {output.link}"

rule gsnap_all:
	input: expand(ALIGN_DIR+"/output/gsnap-{sample}-{run}.bam", sample=SAMPLES, run=GSNAP_RUNS)
	output: ALIGN_DIR+"/gsnap.done"
	shell: "touch {output}"	


rule align_star_index:
	input: os.path.abspath(REF)
	output: ALIGN_DIR +"/star/index/SAindex"
	params: 
		indexdir=ALIGN_DIR_FULL+"/star/index",
		load=loadPre(config["load"]["star"]),
		trans="--sjdbGTFfile " + os.path.abspath(REF_TRANS) if REF_TRANS else "",
		extra=config["extra"]["star_index"]
	log: ALIGN_DIR_FULL+"/star.index.log"
	threads: THREADS
	message: "Indexing genome with star"
	shell: "{params.load} cd {ALIGN_DIR_FULL}/star && STAR --runThreadN {threads} --runMode genomeGenerate --genomeDir {params.indexdir} {params.trans} --genomeFastaFiles {input} {params.extra} > {log} 2>&1 && cd {CWD}"


rule align_star:
	input:
		r1=lambda wildcards: INPUT_1_MAP[wildcards.sample],
		index=rules.align_star_index.output
	output:
		bam=ALIGN_DIR+"/star/{sample}-{run,\d+}/Aligned.out.bam",
		link=ALIGN_DIR+"/output/star-{sample}-{run,\d+}.bam"
	params:
		outdir=ALIGN_DIR_FULL+"/star/{sample}-{run}",
		indexdir=ALIGN_DIR_FULL+"/star/index",
		load=loadPre(config["load"]["star"]),
		extra=lambda wildcards: config["align_methods"]["star"][int(wildcards.run)],
		link_src="../star/{sample}-{run}/Aligned.out.bam",
		trans="--sjdbGTFfile " + os.path.abspath(REF_TRANS) if REF_TRANS else "",
		rfc=lambda wildcards: starCompressionOption(wildcards.sample),
		infiles=lambda wildcards: starInput(wildcards.sample)		
	log: ALIGN_DIR_FULL+"/star-{sample}-{run}.log"
	threads: int(THREADS)
	message: "Aligning input with star (sample {wildcards.sample} - run {wildcards.run})"
	shell: "{params.load} cd {params.outdir}; STAR --runThreadN {threads} --runMode alignReads --genomeDir {params.indexdir} {params.rfc} {params.infiles} --outSAMtype BAM Unsorted --outSAMattributes NH HI AS nM XS NM MD --outSAMstrandField intronMotif --alignIntronMin {MIN_INTRON} --alignIntronMax {MAX_INTRON} {params.trans} --alignMatesGapMax {MAX_INTRON} --outFileNamePrefix {params.outdir}/ {params.extra} > {log} 2>&1 && cd {CWD} && ln -sf {params.link_src} {output.link} && touch -h {output.link}"

rule star_all:
	input: expand(ALIGN_DIR+"/output/star-{sample}-{run}.bam", sample=SAMPLES, run=STAR_RUNS)
	output: ALIGN_DIR+"/star.done"
	shell: "touch {output}"	

rule align_hisat_index:
	input: REF
	output: ALIGN_DIR+"/hisat/index/"+NAME+".4.ht2"
	params: load=loadPre(config["load"]["hisat"])
	log: ALIGN_DIR+"/hisat.index.log"
	threads: 1
	message: "Indexing genome with hisat"
	shell: "{params.load} hisat2-build {input} {ALIGN_DIR}/hisat/index/{NAME} > {log} 2>&1"

rule align_hisat:
	input:
		r1=lambda wildcards: INPUT_1_MAP[wildcards.sample],
		index=rules.align_hisat_index.output
	output:
		bam=ALIGN_DIR+"/hisat/{sample}-{run,\d+}/hisat.bam",
		link=ALIGN_DIR+"/output/hisat-{sample}-{run,\d+}.bam"
	params:
		indexdir=ALIGN_DIR+"/hisat/index/"+NAME,
		load=loadPre(config["load"]["hisat"]),
		load_samtools=loadPre(config["load"]["samtools"]),
		link_src="../hisat/{sample}-{run}/hisat.bam",
		extra=lambda wildcards: config["align_methods"]["hisat"][int(wildcards.run)],
		ss_gen="hisat2_extract_splice_sites.py " + REF_TRANS + " > " + ALIGN_DIR + "/hisat/{sample}-{run}/splice_sites.txt &&" if REF_TRANS else "",
		trans="--known-splicesite-infile=" + ALIGN_DIR + "/hisat/{sample}-{run}/splice_sites.txt" if REF_TRANS else "",
		strand=lambda wildcards: hisatStrandOption(wildcards.sample),
		infiles=lambda wildcards: hisatInput(wildcards.sample)
	log: ALIGN_DIR+"/hisat-{sample}-{run}.log"
	threads: THREADS
	message: "Aligning input with hisat (sample {wildcards.sample} - run {wildcards.run})"
    	shell: "{params.load} {params.load_samtools} {params.ss_gen} hisat2 -p {threads} --min-intronlen={MIN_INTRON} --max-intronlen={MAX_INTRON} {params.trans} {params.strand} {params.extra} -x {params.indexdir} --dta-cufflinks {params.infiles} 2> {log} | samtools view -b -@ {threads} - > {output.bam} && ln -sf {params.link_src} {output.link} && touch -h {output.link}"

rule hisat_all:
	input: expand(ALIGN_DIR+"/output/hisat-{sample}-{run}.bam", sample=SAMPLES, run=HISAT_RUNS)
	output: ALIGN_DIR+"/hisat.done"
	shell: "touch {output}"	


rule bam_sort:
	input: bam=ALIGN_DIR+"/output/{align_run}.bam"
	output: ALIGN_DIR+"/output/{align_run}.sorted.bam"
	params:
		load=loadPre(config["load"]["samtools"]),
		temp=ALIGN_DIR+"/sort_{align_run}"
	threads: int(THREADS)
	message: "Using samtools to sort {input.bam}"
	shell: "{params.load} samtools sort -o {output} -O bam -m 1G -T {params.temp} -@ {threads} {input.bam}"


rule bam_index:
	input: rules.bam_sort.output
	output: ALIGN_DIR+"/output/{align_run}.sorted.bam.bai"
	params: load=loadPre(config["load"]["samtools"])
	threads: 1
	message: "Using samtools to index: {input}"
	shell: "{params.load} samtools index {input}"


rule bam_stats:
	input:
		bam=rules.bam_sort.output,
		idx=rules.bam_index.output
	output: ALIGN_DIR+"/output/{align_run}.sorted.bam.stats"
	params: 
		load=loadPre(config["load"]["samtools"]),
		plot_out=ALIGN_DIR+"/output/plots/{align_run}/{align_run}"
	threads: 1
	message: "Using samtools to collected stats for: {input}"
	shell: "{params.load} samtools stats {input.bam} > {output} && plot-bamstats -p {params.plot_out} {output}"


rule align_all:
	input: expand(ALIGN_DIR+"/output/{align_run}.sorted.bam.stats", align_run=ALIGN_RUNS)
	output: ALIGN_DIR+"/output/all.done"
	threads: 1
	shell: "touch {output}"

rule align_collect_stats:
	input: rules.align_all.output
	output: ALIGN_DIR+"/alignment.stats"
	params: stats=ALIGN_DIR+"/output/*.sorted.bam.stats"
	threads: 1
	message: "Collecting alignment stats"
	shell: "{ALIGN_COLLECT} {params.stats} > {output}"
		

rule asm_cufflinks:
	input: 
		bam=ALIGN_DIR+"/output/{alrun}.sorted.bam",
		align=rules.align_all.output,
		ref=REF
	output: 
		gtf=ASM_DIR+"/output/cufflinks-{run2,\d+}-{alrun}.gtf"
	params: 
		outdir=ASM_DIR+"/cufflinks-{run2}-{alrun}",
		gtf=ASM_DIR+"/cufflinks-{run2}-{alrun}/transcripts.gtf",
		link_src="../cufflinks-{run2}-{alrun}/transcripts.gtf",
		load=loadPre(config["load"]["cufflinks"]),
		extra=lambda wildcards: config["asm_methods"]["cufflinks"][int(wildcards.run2)],
		trans="--GTF-guide=" + REF_TRANS if REF_TRANS else "",
		strand=lambda wildcards: tophatStrandOption(extractSample(wildcards.alrun))
	log: ASM_DIR+"/cufflinks-{run2}-{alrun}.log"
	threads: THREADS
	message: "Using cufflinks to assemble (run {wildcards.run2}): {input.bam}"
	shell: "{params.load} cufflinks --output-dir={params.outdir} --num-threads={threads} {params.trans} {params.strand} --min-intron-length={MIN_INTRON} --max-intron-length={MAX_INTRON} --no-update-check {params.extra} {input.bam} > {log} 2>&1 && ln -sf {params.link_src} {output.gtf} && touch -h {output.gtf}"


rule cufflinks_all:
	input: expand(ASM_DIR+"/output/cufflinks-{run2}-{alrun}.gtf", run2=CUFFLINKS_RUNS, alrun=ALIGN_RUNS)
	output: ASM_DIR+"/cufflinks.done"
	shell: "touch {output}"	

rule asm_trinitygg:
	input:
		bam=ALIGN_DIR+"/output/{alrun}.sorted.bam",
		align=rules.align_all.output,
		ref=REF
	output: ASM_DIR+"/trinity-{run2,\d+}-{alrun}/Trinity-GG.fasta"
	params: 
		outdir=ASM_DIR+"/trinity-{run2}-{alrun}",
		load=loadPre(config["load"]["trinity"]),
		extra=lambda wildcards: config["asm_methods"]["trinity"][int(wildcards.run2)],
		strand=lambda wildcards: trinityStrandOption(extractSample(wildcards.alrun)),
		base_parameters=lambda wildcards: trinityParameters(config["load"]["trinity"], extractSample(wildcards.alrun), REF, TGG_MAX_MEM)
	log: ASM_DIR+"/trinity-{run2}-{alrun}.log"
	threads: THREADS
	message: "Using trinity in genome guided mode to assemble (run {wildcards.run2}): {input.bam}"
	shell: "{params.load} Trinity --seqType=fq {params.strand} --output={params.outdir} {params.extra} --genome_guided_max_intron={MAX_INTRON}  --CPU={threads}  {params.base_parameters}={input.bam} > {log} 2>&1"

rule gmap_index:
        input: REF
        output: ALIGN_DIR +"/gmap/index/"+NAME+"/"+NAME+".sachildguide1024"
	params:	load=loadPre(config["load"]["gmap"])
	threads: 1
        log: ALIGN_DIR+"/gmap.index.log"
        message: "Indexing genome with gmap"
        shell: "{params.load} gmap_build --dir={ALIGN_DIR}/gmap/index --db={NAME} {input} > {log} 2>&1"


rule asm_map_trinitygg:
	input: 
		transcripts=rules.asm_trinitygg.output,
		index=rules.gmap_index.output
	output: 
		gff=ASM_DIR+"/output/trinity-{run2,\d+}-{alrun}.gff"
	params: 
		load=loadPre(config["load"]["gmap"]),
		gff=ASM_DIR+"/trinity-{run2}-{alrun}/trinity-{run2}-{alrun}.gff",
		link_src="../trinity-{run2}-{alrun}/trinity-{run2}-{alrun}.gff",
		intron_length=gmap_intron_lengths(loadPre(config["load"]["gmap"]), MAX_INTRON)
	log: ASM_DIR+"/trinitygmap-{run2}-{alrun}.log"
	threads: THREADS
	message: "Mapping trinity transcripts to the genome (run {wildcards.run2}): {input.transcripts}"
	shell: "{params.load} gmap --dir={ALIGN_DIR}/gmap/index --db={NAME} --min-intronlength={MIN_INTRON} {params.intron_length}  --format=3 {input.transcripts} > {params.gff} 2> {log} && ln -sf {params.link_src} {output.gff} && touch -h {output.gff}"

rule trinity_all:
	input: expand(ASM_DIR+"/output/trinity-{run2}-{alrun}.gff", run2=TRINITY_RUNS, alrun=ALIGN_RUNS)
	output: ASM_DIR+"/trinity.done"
	shell: "touch {output}"	


rule lr_gmap:
	input:
		index=rules.gmap_index.output,
		reads=lambda wildcards: L_INPUT_MAP[wildcards.lsample]
	output: link=ALIGN_DIR+"/lr_output/lr_gmap-{lsample}-{lrun}.gff",
		gff=ALIGN_DIR+"/gmap/{lsample}-{lrun}/lr_gmap-{lsample}-{lrun}.gff"		
	params: load=loadPre(config["load"]["gmap"]),
		link_src="../gmap/{lsample}-{lrun}/lr_gmap-{lsample}-{lrun}.gff"
	log: ALIGN_DIR+"/gmap-{lsample}-{lrun}.log"
	threads: THREADS
	message: "Mapping long reads to the genome with gmap (sample: {wildcards.lsample} - run: {wildcards.lrun})"
	shell: "{params.load} gmap --dir={ALIGN_DIR}/gmap/index --db={NAME} --min-intronlength={MIN_INTRON} --max-intronlength-middle={MAX_INTRON} --max-intronlength-ends={MAX_INTRON}  --format=3 {input.reads} > {output.gff} 2> {log} && ln -sf {params.link_src} {output.link} && touch -h {output.link}"

rule lr_star:
	input:
		index=rules.align_star_index.output,
		reads=lambda wildcards: L_INPUT_MAP[wildcards.lsample]
	output: bam=ALIGN_DIR+"/lr_star/{lsample}-{lrun}/Aligned.out.bam"
	params: load=loadPre(config["load"]["star"]),
		outdir=ALIGN_DIR_FULL+"/lr_star/{lsample}-{lrun}",
                indexdir=ALIGN_DIR_FULL+"/star/index",
                trans="--sjdbGTFfile " + os.path.abspath(REF_TRANS) if REF_TRANS else "",
                #rfc=lambda wildcards: starCompressionOption(wildcards.lsample),
                infiles=lambda wildcards: starLongInput(wildcards.lsample)
	log: ALIGN_DIR_FULL+"/lr_star-{lsample}-{lrun}.log"
	threads: THREADS
	message: "Mapping long reads to the genome with star (sample: {wildcards.lsample} - run: {wildcards.lrun})"
	shell: "{params.load} STARlong --runThreadN {threads} --runMode alignReads --outSAMattributes NH HI NM MD --readNameSeparator space --outFilterMultimapScoreRange 1 --outFilterMismatchNmax 2000 --scoreGapNoncan -20 --scoreGapGCAG -4 --scoreGapATAC -8 --scoreDelOpen -1 --scoreDelBase -1 --scoreInsOpen -1 --scoreInsBase -1 --alignEndsType Local --seedSearchStartLmax 50 --seedPerReadNmax 100000 --seedPerWindowNmax 1000 --alignTranscriptsPerReadNmax 100000 --alignTranscriptsPerWindowNmax 10000 --genomeDir {params.indexdir} {params.infiles} --outSAMtype BAM Unsorted --outSAMstrandField intronMotif --alignIntronMin {MIN_INTRON} --alignIntronMax {MAX_INTRON} {params.trans} --outFileNamePrefix {params.outdir}/ > {log} 2>&1 && cd {CWD}"


rule starbam2gtf:
	input: rules.lr_star.output.bam
	output: gtf=ALIGN_DIR+"/lr_output/lr_star-{lsample}-{lrun}.gtf"
	params: load=loadPre(config["load"]["mikado"])
	message: "Converting STAR long reads from BAM to GTF (sample: {wildcards.lsample} - run: {wildcards.lrun})"
	shell: "{params.load} bam2gtf.py {input} > {output.gtf}"


rule lr_gmap_all:
	input: expand(ALIGN_DIR+"/lr_output/lr_gmap-{lsample}-{lrun}.gff", lsample=L_SAMPLES, lrun=LR_GMAP_RUNS)
	output: ALIGN_DIR+"/lr_gmap.done"
	shell: "touch {output}"	

rule lr_star_all:
	input: expand(ALIGN_DIR+"/lr_output/lr_star-{lsample}-{lrun}.gtf", lsample=L_SAMPLES, lrun=LR_STAR_RUNS)
	output: ALIGN_DIR+"/lr_star.done"
	shell: "touch {output}"	

rule asm_stringtie:
	input: 
		bam=ALIGN_DIR+"/output/{alrun}.sorted.bam",
		align=rules.align_all.output
	output: 
		link=ASM_DIR+"/output/stringtie-{run2,\d+}-{alrun}.gtf",
		gtf=ASM_DIR+"/stringtie-{run2,\d+}-{alrun}/stringtie-{run2}-{alrun}.gtf"
	params:
		load=loadPre(config["load"]["stringtie"]),
		extra=lambda wildcards: config["asm_methods"]["stringtie"][int(wildcards.run2)],
		gtf=ASM_DIR+"/stringtie-{run2}-{alrun}/stringtie-{run2}-{alrun}.gtf",
		trans="-G " + REF_TRANS if REF_TRANS else "",
		link_src="../stringtie-{run2}-{alrun}/stringtie-{run2}-{alrun}.gtf"
	log: ASM_DIR+"/stringtie-{run2}-{alrun}.log"
	threads: THREADS
	message: "Using stringtie to assemble (run {wildcards.run2}): {input.bam}"
	shell: "{params.load} stringtie {input.bam} -l Stringtie_{wildcards.run2}_{wildcards.alrun} -f 0.05 -m 200 {params.extra} {params.trans} -o {params.gtf} -p {threads} > {log} 2>&1 && ln -sf {params.link_src} {output.link} && touch -h {output.link}"

rule stringtie_all:
	input: expand(ASM_DIR+"/output/stringtie-{run2}-{alrun}.gtf", run2=STRINGTIE_RUNS, alrun=ALIGN_RUNS)
	output: ASM_DIR+"/stringtie.done"
	shell: "touch {output}"	

rule asm_class:
	input:
		bam=ALIGN_DIR+"/output/{alrun}.sorted.bam",
		align=rules.align_all.output,
		ref=REF
	output: 
		link=ASM_DIR+"/output/class-{run2,\d+}-{alrun}.gtf",
		gtf=ASM_DIR+"/class-{run2,\d+}-{alrun}/class-{run2}-{alrun}.gtf"
	params: 
		outdir=ASM_DIR+"/class-{run2}-{alrun}",
		load=loadPre(config["load"]["class"]),
		extra=lambda wildcards: config["asm_methods"]["class"][int(wildcards.run2)],
		link_src="../class-{run2}-{alrun}/class-{run2}-{alrun}.gtf"
	log: ASM_DIR+"/class-{run2}-{alrun}.log"
	threads: THREADS
	message: "Using class to assemble (run {wildcards.run2}): {input.bam}"
	shell: "{params.load} {CLASS} --clean --force -c \"{params.extra}\" -p {threads} {input.bam} > {output.gtf} 2> {log} && ln -sf {params.link_src} {output.link} && touch -h {output.link}"

rule class_all:
	input: expand(ASM_DIR+"/output/class-{run2}-{alrun}.gtf", run2=CLASS_RUNS, alrun=ALIGN_RUNS)
	output: ASM_DIR+"/class.done"
	shell: "touch {output}"	

rule asm_gff_stats:
	input: ASM_DIR + "/output/{asm_run}"
	output: ASM_DIR + "/output/{asm_run}.stats"
	params: load=loadPre(config["load"]["mikado"])
	threads: 1
	message: "Computing assembly stats for: {input}"
	shell: "{params.load} mikado util stats {input} > {output}"


rule asm_all:
	input: expand("{asm_run}.stats", asm_run=TRANSCRIPT_ARRAY)
	output:	ASM_DIR+"/output/all.done"
	threads: 1
	shell: "touch {output}"

rule lreads_stats:
	input: ALIGN_DIR + "/lr_output/{lr_run}"
	output: ALIGN_DIR + "/lr_output/{lr_run}.stats"
	params: load=loadPre(config["load"]["mikado"])
	threads: 1
	message: "Computing long read stats for: {input}"
	shell: "{params.load} mikado util stats {input} > {output}"


rule lreads_all:
	input: expand("{lr_run}.stats", lr_run=LR_ARRAY)
	output: ALIGN_DIR+"/lr_output/lreads.all.done"
	threads: 1
	shell: "touch {output}"

rule asm_collect_stats:
	input: rules.asm_all.output
	output: ASM_DIR+"/assembly.stats"
	params: asms=ASM_DIR+"/output/*.stats"
	threads: 1
	message: "Collecting assembly statistics"
	shell: "{ASM_COLLECT} {params.asms} > {output}"

rule portcullis_prep:
	input:	ref=REF,
		aln_done=rules.align_all.output
	output: PORTCULLIS_DIR+"/portcullis_{aln_method}/1-prep/portcullis.sorted.alignments.bam.bai"
	params: 
		outdir=PORTCULLIS_DIR+"/portcullis_{aln_method}/1-prep",
		load=loadPre(config["load"]["portcullis"]),
		files=lambda wildcards: PORTCULLIS_IN[wildcards.aln_method],
		strand=lambda wildcards: portcullisStrandOption(wildcards.aln_method, loadPre(config["load"]["portcullis"]), "prep")
	log: PORTCULLIS_DIR+"/portcullis_{aln_method}-prep.log"
	threads: THREADS
	message: "Using portcullis to prepare: {wildcards.aln_method}"
	shell: "{params.load} portcullis prep -o {params.outdir} {params.strand} -t {threads} {input.ref} {params.files} > {log} 2>&1"


rule portcullis_junc:
	input: 
		bai=rules.portcullis_prep.output
	output: PORTCULLIS_DIR+"/portcullis_{aln_method}/2-junc/{aln_method}.junctions.tab"
	params: 
		prepdir=PORTCULLIS_DIR+"/portcullis_{aln_method}/1-prep",
		outdir=PORTCULLIS_DIR+"/portcullis_{aln_method}/2-junc",
		load=loadPre(config["load"]["portcullis"]),
		strand=lambda wildcards: portcullisStrandOption(wildcards.aln_method, loadPre(config["load"]["portcullis"]), "junc")
	log: PORTCULLIS_DIR+"/portcullis_{aln_method}-junc.log"
	threads: THREADS
	message: "Using portcullis to analyse potential junctions: {wildcards.aln_method}"
	shell: "{params.load} portcullis junc -o {params.outdir}/{wildcards.aln_method} {params.strand} -t {threads} {params.prepdir} > {log} 2>&1"

rule portcullis_filter:
	input: rules.portcullis_junc.output
	output:		
		link=PORTCULLIS_DIR+"/output/portcullis_{aln_method}.pass.junctions.bed"
	params: 
		outdir=PORTCULLIS_DIR+"/portcullis_{aln_method}/3-filt",
		prepdir=PORTCULLIS_DIR+"/portcullis_{aln_method}/1-prep/",
		load=loadPre(config["load"]["portcullis"]),
		bed=PORTCULLIS_DIR+"/portcullis_{aln_method}/3-filt/{aln_method}.pass.junctions.bed",
		ss_gen="mkdir -p " + PORTCULLIS_DIR + "/portcullis_{aln_method}/3-filt && gtf2bed.py " + REF_TRANS + " > " + PORTCULLIS_DIR + "/portcullis_{aln_method}/3-filt/ref_juncs.bed &&" if REF_TRANS else "",
		trans="--reference=" + PORTCULLIS_DIR + "/portcullis_{aln_method}/3-filt/ref_juncs.bed" if REF_TRANS else "",
		link_src="../portcullis_{aln_method}/3-filt/{aln_method}.pass.junctions.bed",
		link_unfilt="../portcullis_{aln_method}/2-junc/{aln_method}.junctions.bed"
	log: PORTCULLIS_DIR+"/portcullis_{aln_method}-filter.log"
	threads: THREADS
	message: "Using portcullis to filter invalid junctions: {wildcards.aln_method}"
	shell: "{params.load} {params.ss_gen} portcullis filter -o {params.outdir}/{wildcards.aln_method} --canonical={CANONICAL_JUNCS} --max_length={MAX_INTRON} {params.trans} --threads={threads} {params.prepdir} {input} > {log} 2>&1 && ln -sf {params.link_src} {output.link} || ln -sf {params.link_unfilt} {output.link} && touch -h {output.link}"

rule portcullis_merge:
	input: expand(PORTCULLIS_DIR + "/output/portcullis_{aln_method}.pass.junctions.bed", aln_method=ALIGN_RUNS)
	output: bed=PORTCULLIS_DIR + "/output/portcullis.merged.bed"
	params: load=loadPre(config["load"]["portcullis"])
	log: PORTCULLIS_DIR + "/output/portcullis.merged.log"
	threads: 1
	message: "Taking intersection of portcullis results"
	run:
		if RUN_PORTCULLIS:
			shell("{params.load} junctools set --prefix=portcullis_merged --output={output.bed} --operator=mean union {input} > {log} || touch {output.bed}")
		else:
			shell("touch {output}")


#### Now run mikado
rule mikado_cfg:
	input:
		asm=rules.asm_all.output,
		lr=rules.lreads_all.output,
		portcullis=rules.portcullis_merge.output,
		cfg=CFG,
		ref=REF
	output:
		mikado=OUT_DIR + "/mikado.yaml"
	params: 
		load=loadPre(config["load"]["mikado"]),
		scoring=config["mikado"]["pick"]["scoring_file"],
		junctions="--junctions={}".format(rules.portcullis_merge.output.bed)
	log: OUT_DIR + "/mikado.yaml.log"
	threads: 1
	message: "Creating Mikado configuration file"
	shell: "{params.load} mikado configure --full --gff={MIKADO_IN_STR} --labels={MIKADO_LABEL_STR} --strand-specific-assemblies={MIKADO_SS_STR} {params.junctions} --scoring {params.scoring} --reference={input.ref} --external={input.cfg} {output} 2> {log}"

