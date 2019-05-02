#!/usr/bin/env nextflow
/*
========================================================================================
                         nf-core/sarek
========================================================================================
New Germline (+ Somatic) Analysis Workflow. Started March 2016.
----------------------------------------------------------------------------------------
 nf-core/sarek Analysis Pipeline.
 @Homepage
 https://sarek.scilifelab.se/
 @Documentation
 https://github.com/nf-core/sarek/README.md
----------------------------------------------------------------------------------------
*/

def helpMessage() {
    // TODO nf-core: Add to this help message with new command line parameters
    log.info nfcoreHeader()
    log.info"""

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run nf-core/sarek --sample sample.tsv -profile docker

    Mandatory arguments:
      --sample                      Path to TSV input file
      -profile                      Configuration profile to use. Can use multiple (comma separated)
                                    Available: conda, docker, singularity, awsbatch, test and more.

    Options:
      --genome                      Name of iGenomes reference

    References                      If not specified in the configuration file or you wish to overwrite any of the references.
      --fasta                       Path to Fasta reference

    Other options:
      --outdir                      The output directory where the results will be saved
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      --maxMultiqcEmailFileSize     Theshold size for MultiQC report to be attached in notification email. If file generated by pipeline exceeds the threshold, it will not be attached (Default: 25MB)
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.

    AWSBatch options:
      --awsqueue                    The AWSBatch JobQueue that needs to be set when running on AWSBatch
      --awsregion                   The AWS Region for your AWS Batch job to run on
    """.stripIndent()
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Show help message
if (params.help){
    helpMessage()
    exit 0
}

// Check if genome exists in the config file
if (params.genomes && params.genome && !params.genomes.containsKey(params.genome)) {
    exit 1, "The provided genome '${params.genome}' is not available in the iGenomes file. Currently the available genomes are ${params.genomes.keySet().join(", ")}"
}

params.noReports = false
params.sampleDir = false
params.sequencing_center = null
params.step = 'mapping'
params.targetBED = null
params.test = false
params.tools = false

stepList = defineStepList()
step = params.step ? params.step.toLowerCase() : ''
if (step == 'preprocessing' || step == '') step = 'mapping'
if (!checkParameterExistence(step, stepList)) exit 1, 'Unknown step, see --help for more information'
if (step.contains(',')) exit 1, 'You can choose only one step, see --help for more information'
if (step == 'mapping' && ([params.test, params.sample, params.sampleDir].size == 1))
  exit 1, 'Please define which samples to work on by providing exactly one of the --test, --sample or --sampleDir options'

tools = params.tools ? params.tools.split(',').collect{it.trim().toLowerCase()} : []
toolList = defineToolList()
if (!checkParameterList(tools,toolList)) exit 1, 'Unknown tool(s), see --help for more information'

referenceMap = defineReferenceMap(step, tools)
if (!checkReferenceMap(referenceMap)) exit 1, 'Missing Reference file(s), see --help for more information'

// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if ( !(workflow.runName ==~ /[a-z]+_[a-z]+/) ){
  custom_runName = workflow.runName
}

if ( workflow.profile == 'awsbatch') {
  // AWSBatch sanity checking
  if (!params.awsqueue || !params.awsregion) exit 1, "Specify correct --awsqueue and --awsregion parameters on AWSBatch!"
  // Check outdir paths to be S3 buckets if running on AWSBatch
  // related: https://github.com/nextflow-io/nextflow/issues/813
  if (!params.outdir.startsWith('s3:')) exit 1, "Outdir not on S3 - specify S3 Bucket to run on AWSBatch!"
  // Prevent trace files to be stored on S3 since S3 does not support rolling files.
  if (workflow.tracedir.startsWith('s3:')) exit 1, "Specify a local tracedir or run without trace! S3 cannot be used for tracefiles."
}

// Stage config files
ch_multiqc_config = Channel.fromPath(params.multiqc_config)
ch_output_docs = Channel.fromPath("$baseDir/docs/output.md")

/*
 * Create a channel for input read files
 */
 tsvPath = ''
 if (params.sample) tsvPath = params.sample

 // No need for tsv file for step annotate
 if (!params.sample && !params.sampleDir) {
   tsvPaths = [
       'mapping':        "${workflow.projectDir}/Sarek-data/testdata/tsv/tiny.tsv",
       'recalibrate':    "${params.outdir}/Preprocessing/TSV/duplicateMarked.tsv",
       'variantcalling': "${params.outdir}/Preprocessing/TSV/recalibrated.tsv"
   ]
   if (params.test || step != 'mapping') tsvPath = tsvPaths[step]
 }

 // Set up the inputFiles and bamFiles channels. One of them will remain empty
 inputFiles = Channel.empty()
 bamFiles = Channel.empty()
 if (tsvPath) {
   tsvFile = file(tsvPath)
   switch (step) {
     case 'mapping': inputFiles = extractSample(tsvFile); break
     case 'recalibrate': bamFiles = extractRecal(tsvFile); break
     default: exit 1, "Unknown step ${step}"
   }
 } else if (params.sampleDir) {
   if (step != 'mapping') exit 1, '--sampleDir does not support steps other than "mapping"'
   inputFiles = extractFastqFromDir(params.sampleDir)
   (inputFiles, fastqTmp) = inputFiles.into(2)
   fastqTmp.toList().subscribe onNext: {
     if (it.size() == 0) {
       exit 1, "No FASTQ files found in --sampleDir directory '${params.sampleDir}'"
     }
   }
   tsvFile = params.sampleDir  // used in the reports
 } else exit 1, 'No sample were defined, see --help'

 if (step == 'recalibrate') (patientGenders, bamFiles) = extractGenders(bamFiles)
 else (patientGenders, inputFiles) = extractGenders(inputFiles)

// Header log info
log.info nfcoreHeader()
def summary = [:]
if (workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Run Name']         = custom_runName ?: workflow.runName
// TODO nf-core: Report custom parameters here
summary['Max Resources']    = "$params.max_memory memory, $params.max_cpus cpus, $params.max_time time per job"
if (workflow.containerEngine) summary['Container'] = "$workflow.containerEngine - $workflow.container"
summary['Output dir']       = params.outdir
summary['Launch dir']       = workflow.launchDir
summary['Working dir']      = workflow.workDir
summary['Script dir']       = workflow.projectDir
summary['User']             = workflow.userName
if (workflow.profile == 'awsbatch'){
   summary['AWS Region']    = params.awsregion
   summary['AWS Queue']     = params.awsqueue
}
summary['Config Profile'] = workflow.profile
if (params.config_profile_description) summary['Config Description'] = params.config_profile_description
if (params.config_profile_contact)     summary['Config Contact']     = params.config_profile_contact
if (params.config_profile_url)         summary['Config URL']         = params.config_profile_url
if (params.email) {
  summary['E-mail Address']  = params.email
  summary['MultiQC maxsize'] = params.maxMultiqcEmailFileSize
}
log.info summary.collect { k,v -> "${k.padRight(18)}: $v" }.join("\n")
log.info "\033[2m----------------------------------------------------\033[0m"

// Check the hostnames against configured profiles
checkHostname()

def create_workflow_summary(summary) {
    def yaml_file = workDir.resolve('workflow_summary_mqc.yaml')
    yaml_file.text  = """
    id: 'nf-core-sarek-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'nf-core/sarek Workflow Summary'
    section_href: 'https://github.com/nf-core/sarek'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
${summary.collect { k,v -> "            <dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }.join("\n")}
        </dl>
    """.stripIndent()

   return yaml_file
}

/*
 * Parse software version numbers
 */
process get_software_versions {
    publishDir path:"${params.outdir}/pipeline_info", mode: params.publishDirMode

    output:
    file 'software_versions_mqc.yaml' into software_versions_yaml

    script:
    """
    alleleCounter --version &> v_allelecount.txt  || true
    bcftools version > v_bcftools.txt 2>&1 || true
    bwa &> v_bwa.txt 2>&1 || true
    cat ${baseDir}/scripts/ascat.R | grep "ASCAT version" &> v_ascat.txt  || true
    configManta.py --version > v_manta.txt 2>&1 || true
    configureStrelkaGermlineWorkflow.py --version > v_strelka.txt 2>&1 || true
    echo "${workflow.manifest.version}" &> v_pipeline.txt 2>&1 || true
    echo "${workflow.nextflow.version}" &> v_nextflow.txt 2>&1 || true
    echo "SNPEFF version"\$(snpEff -h 2>&1) > v_snpeff.txt
    fastqc --version > v_fastqc.txt 2>&1 || true
    freebayes --version > v_freebayes.txt 2>&1 || true
    gatk ApplyBQSR --help 2>&1 | grep Version: > v_gatk.txt 2>&1 || true
    multiqc --version &> v_multiqc.txt 2>&1 || true
    qualimap --version &> v_qualimap.txt 2>&1 || true
    R --version &> v_r.txt  || true
    samtools --version &> v_samtools.txt 2>&1 || true
    vcftools --version &> v_vcftools.txt 2>&1 || true
    vep --help &> v_vep.txt 2>&1 || true

    scrape_software_versions.py &> software_versions_mqc.yaml
    """
}

/*
========================================================================================
                         PREPROCESSING
========================================================================================
*/

// STEP ONE: MAPPING

(inputFiles, inputFilesforFastQC) = inputFiles.into(2)

inputFiles = inputFiles.dump(tag:'INPUT')

process RunFastQC {
  tag {idPatient + "-" + idRun}

  publishDir "${params.outdir}/Reports/${idSample}/FastQC/${idRun}", mode: params.publishDirMode

  input:
    set idPatient, status, idSample, idRun, file(inputFile1), file(inputFile2) from inputFilesforFastQC

  output:
    file "*_fastqc.{zip,html}" into fastQCreport

  when: step == 'mapping' && !params.noReports

  script:
  inputFiles = (hasExtension(inputFile1,"fastq.gz") || hasExtension(inputFile1,"fq.gz")) ? "${inputFile1} ${inputFile2}" : "${inputFile1}"
  """
  fastqc -t 2 -q ${inputFiles}
  """
}

fastQCreport.dump(tag:'FastQC')

process MapReads {
  tag {idPatient + "-" + idRun}

  input:
    set idPatient, status, idSample, idRun, file(inputFile1), file(inputFile2) from inputFiles
    set file(genomeFile), file(bwaIndex) from Channel.value([referenceMap.genomeFile, referenceMap.bwaIndex])

  output:
    set idPatient, status, idSample, idRun, file("${idRun}.bam") into (mappedBam, mappedBamForQC)

  when: step == 'mapping'

  script:
  CN = params.sequencing_center ? "CN:${params.sequencing_center}\\t" : ""
  readGroup = "@RG\\tID:${idRun}\\t${CN}PU:${idRun}\\tSM:${idSample}\\tLB:${idSample}\\tPL:illumina"
  // adjust mismatch penalty for tumor samples
  extra = status == 1 ? "-B 3" : ""
  if (hasExtension(inputFile1,"fastq.gz") || hasExtension(inputFile1,"fq.gz"))
    """
    bwa mem -K 100000000 -R \"${readGroup}\" ${extra} -t ${task.cpus} -M \
    ${genomeFile} ${inputFile1} ${inputFile2} | \
    samtools sort --threads ${task.cpus} -m 2G - > ${idRun}.bam
    """
  else if (hasExtension(inputFile1,"bam"))
  // -K is an hidden option, used to fix the number of reads processed by bwa mem
  // Chunk size can affect bwa results, if not specified, the number of threads can change
  // which can give not deterministic result.
  // cf https://github.com/CCDG/Pipeline-Standardization/blob/master/PipelineStandard.md
  // and https://github.com/gatk-workflows/gatk4-data-processing/blob/8ffa26ff4580df4ac3a5aa9e272a4ff6bab44ba2/processing-for-variant-discovery-gatk4.b37.wgs.inputs.json#L29
    """
    gatk --java-options -Xmx${task.memory.toGiga()}g \
    SamToFastq \
    --INPUT=${inputFile1} \
    --FASTQ=/dev/stdout \
    --INTERLEAVE=true \
    --NON_PF=true \
    | \
    bwa mem -K 100000000 -p -R \"${readGroup}\" ${extra} -t ${task.cpus} -M ${genomeFile} \
    /dev/stdin - 2> >(tee ${inputFile1}.bwa.stderr.log >&2) \
    | \
    samtools sort --threads ${task.cpus} -m 2G - > ${idRun}.bam
    """
}

mappedBam = mappedBam.dump(tag:'Mapped BAM')

process RunBamQCmapped {
  tag {idPatient + "-" + idSample}

  publishDir "${params.outdir}/Reports/${idSample}/bamQC", mode: params.publishDirMode

  input:
    set idPatient, status, idSample, idRun, file(bam) from mappedBamForQC
    file(targetBED) from Channel.value(params.targetBED ? file(params.targetBED) : "null")

  output:
    file("${bam.baseName}") into bamQCmappedReport

  when: !params.noReports

  script:
  use_bed = params.targetBED ? "-gff ${targetBED}" : ''
  """
  qualimap --java-mem-size=${task.memory.toGiga()}G \
  bamqc \
  -bam ${bam} \
  --paint-chromosome-limits \
  --genome-gc-distr HUMAN \
  $use_bed \
  -nt ${task.cpus} \
  -skip-duplicated \
  --skip-dup-mode 0 \
  -outdir ${bam.baseName} \
  -outformat HTML
  """
}

bamQCmappedReport.dump(tag:'BamQC BAM')

// Sort bam whether they are standalone or should be merged

singleBam = Channel.create()
groupedBam = Channel.create()
mappedBam.groupTuple(by:[0,1,2])
  .choice(singleBam, groupedBam) {it[3].size() > 1 ? 1 : 0}
singleBam = singleBam.map {
  idPatient, status, idSample, idRun, bam ->
  [idPatient, status, idSample, bam]
}

process MergeBams {
  tag {idPatient + "-" + idSample}

  input:
    set idPatient, status, idSample, idRun, file(bam) from groupedBam

  output:
    set idPatient, status, idSample, file("${idSample}.bam") into mergedBam

  when: step == 'mapping'

  script:
  """
  samtools merge --threads ${task.cpus} ${idSample}.bam ${bam}
  """
}

singleBam = singleBam.dump(tag:'Single BAM')
mergedBam = mergedBam.dump(tag:'Merged BAM')
mergedBam = mergedBam.mix(singleBam)
mergedBam = mergedBam.dump(tag:'BAM for MD')

process MarkDuplicates {
  tag {idPatient + "-" + idSample}

  publishDir params.outdir, mode: params.publishDirMode,
    saveAs: {
      if (it == "${idSample}.bam.metrics") "Reports/${idSample}/MarkDuplicates/${it}"
      else "Preprocessing/${idSample}/DuplicateMarked/${it}"
    }

  input:
    set idPatient, status, idSample, file("${idSample}.bam") from mergedBam

  output:
    set idPatient, file("${idSample}_${status}.md.bam"), file("${idSample}_${status}.md.bai") into duplicateMarkedBams
    set idPatient, status, idSample, val("${idSample}_${status}.md.bam"), val("${idSample}_${status}.md.bai") into markDuplicatesTSV
    file ("${idSample}.bam.metrics") into markDuplicatesReport

  when: step == 'mapping'

  script:
  markdup_java_options = task.memory.toGiga() > 8 ? params.markdup_java_options : "\"-Xms" +  (task.memory.toGiga() / 2 ).trunc() + "g -Xmx" + (task.memory.toGiga() - 1) + "g\""
  """
  gatk --java-options ${markdup_java_options} \
  MarkDuplicates \
  --MAX_RECORDS_IN_RAM 50000 \
  --INPUT ${idSample}.bam \
  --METRICS_FILE ${idSample}.bam.metrics \
  --TMP_DIR . \
  --ASSUME_SORT_ORDER coordinate \
  --CREATE_INDEX true \
  --OUTPUT ${idSample}_${status}.md.bam
  """
}

// Creating a TSV file to restart from this step
markDuplicatesTSV.map { idPatient, status, idSample, bam, bai ->
  gender = patientGenders[idPatient]
  "${idPatient}\t${gender}\t${status}\t${idSample}\t${params.outdir}/Preprocessing/${idSample}/DuplicateMarked/${bam}\t${params.outdir}/Preprocessing/${idSample}/DuplicateMarked/${bai}\n"
}.collectFile(
  name: 'duplicateMarked.tsv', sort: true, storeDir: "${params.outdir}/Preprocessing/TSV"
)

duplicateMarkedBams = duplicateMarkedBams.map {
    idPatient, bam, bai ->
    tag = bam.baseName.tokenize('.')[0]
    status   = tag[-1..-1].toInteger()
    idSample = tag.take(tag.length()-2)
    [idPatient, status, idSample, bam, bai]
}

duplicateMarkedBams = duplicateMarkedBams.dump(tag:'MD BAM')

(mdBam, mdBamToJoin) = duplicateMarkedBams.into(2)

process CreateRecalibrationTable {
  tag {idPatient + "-" + idSample}

  publishDir "${params.outdir}/Preprocessing/${idSample}/DuplicateMarked", mode: params.publishDirMode, overwrite: false

  input:
    set idPatient, status, idSample, file(bam), file(bai) from mdBam // realignedBam
    set file(genomeFile), file(genomeIndex), file(genomeDict), file(dbsnp), file(dbsnpIndex), file(knownIndels), file(knownIndelsIndex), file(intervals) from Channel.value([
      referenceMap.genomeFile,
      referenceMap.genomeIndex,
      referenceMap.genomeDict,
      referenceMap.dbsnp,
      referenceMap.dbsnpIndex,
      referenceMap.knownIndels,
      referenceMap.knownIndelsIndex,
      referenceMap.intervals,
    ])

  output:
    set idPatient, status, idSample, file("${idSample}.recal.table") into recalibrationTable
    set idPatient, status, idSample, val("${idSample}_${status}.md.bam"), val("${idSample}_${status}.md.bai"), val("${idSample}.recal.table") into recalibrationTableTSV

  when: step == 'mapping'

  script:
  known = knownIndels.collect{ "--known-sites ${it}" }.join(' ')
  """
  gatk --java-options -Xmx${task.memory.toGiga()}g \
  BaseRecalibrator \
  --input ${bam} \
  --output ${idSample}.recal.table \
  --tmp-dir /tmp \
  -R ${genomeFile} \
  -L ${intervals} \
  --known-sites ${dbsnp} \
  ${known} \
  --verbosity INFO
  """
}

// Create a TSV file to restart from this step
recalibrationTableTSV.map { idPatient, status, idSample, bam, bai, recalTable ->
  gender = patientGenders[idPatient]
  "${idPatient}\t${gender}\t${status}\t${idSample}\t${params.outdir}/Preprocessing/${idSample}/DuplicateMarked/${bam}\t${params.outdir}/Preprocessing/${idSample}/DuplicateMarked/${bai}\t${params.outdir}/Preprocessing/${idSample}/DuplicateMarked/${recalTable}\n"
}.collectFile(
  name: 'duplicateMarked.tsv', sort: true, storeDir: "${params.outdir}/Preprocessing/TSV"
)

recalibrationTable = mdBamToJoin.join(recalibrationTable, by:[0,1,2])

if (step == 'recalibrate') recalibrationTable = bamFiles

recalibrationTable = recalibrationTable.dump(tag:'recal.table')

process RecalibrateBam {
  tag {idPatient + "-" + idSample}

  publishDir "${params.outdir}/Preprocessing/${idSample}/Recalibrated", mode: params.publishDirMode

  input:
    set idPatient, status, idSample, file(bam), file(bai), file(recalibrationReport) from recalibrationTable
    set file(genomeFile), file(genomeIndex), file(genomeDict), file(intervals) from Channel.value([
      referenceMap.genomeFile,
      referenceMap.genomeIndex,
      referenceMap.genomeDict,
      referenceMap.intervals,
    ])

  output:
    set idPatient, status, idSample, file("${idSample}.recal.bam"), file("${idSample}.recal.bai") into recalibratedBam, recalibratedBamForStats
    set idPatient, status, idSample, val("${idSample}.recal.bam"), val("${idSample}.recal.bai") into recalibratedBamTSV

  script:
  """
  gatk --java-options -Xmx${task.memory.toGiga()}g \
  ApplyBQSR \
  -R ${genomeFile} \
  --input ${bam} \
  --output ${idSample}.recal.bam \
  -L ${intervals} \
  --create-output-bam-index true \
  --bqsr-recal-file ${recalibrationReport}
  """
}
// Creating a TSV file to restart from this step
recalibratedBamTSV.map { idPatient, status, idSample, bam, bai ->
  gender = patientGenders[idPatient]
  "${idPatient}\t${gender}\t${status}\t${idSample}\t${params.outdir}/Preprocessing/${idSample}/Recalibrated/${bam}\t${params.outdir}/Preprocessing/${idSample}/Recalibrated/${bai}\n"
}.collectFile(
  name: 'recalibrated.tsv', sort: true, storeDir: "${params.outdir}/Preprocessing/TSV"
)

recalibratedBam.dump(tag:'recal.bam')

// Remove recalTable from Channels to match inputs for Process to avoid:
// WARN: Input tuple does not match input set cardinality declared by process...
(bamForBamQC, bamForSamToolsStats) = recalibratedBamForStats.map{ it[0..4] }.into(2)

process RunSamtoolsStats {
  tag {idPatient + "-" + idSample}

  publishDir "${params.outdir}/Reports/${idSample}/SamToolsStats", mode: params.publishDirMode

  input:
    set idPatient, status, idSample, file(bam), file(bai) from bamForSamToolsStats

  output:
    file ("${bam}.samtools.stats.out") into samtoolsStatsReport

  when: !params.noReports

  script:
  """
  samtools stats ${bam} > ${bam}.samtools.stats.out
  """
}

samtoolsStatsReport.dump(tag:'SAMTools')

process RunBamQCrecalibrated {
  tag {idPatient + "-" + idSample}

  publishDir "${params.outdir}/Reports/${idSample}/bamQC", mode: params.publishDirMode

  input:
    set idPatient, status, idSample, file(bam), file(bai) from bamForBamQC

  output:
    file("${bam.baseName}") into bamQCrecalibratedReport

  when: !params.noReports

  script:
  """
  qualimap --java-mem-size=${task.memory.toGiga()}G \
  bamqc \
  -bam ${bam} \
  --paint-chromosome-limits \
  --genome-gc-distr HUMAN \
  -nt ${task.cpus} \
  -skip-duplicated \
  --skip-dup-mode 0 \
  -outdir ${bam.baseName} \
  -outformat HTML
  """
}

bamQCrecalibratedReport.dump(tag:'BamQC')

/*
 * Completion e-mail notification
 */
workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[nf-core/sarek] Successful: $workflow.runName"
    if (!workflow.success){
      subject = "[nf-core/sarek] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if (workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if (workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if (workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    if (workflow.container) email_fields['summary']['Docker image'] = workflow.container
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp

    // TODO nf-core: If not using MultiQC, strip out this code (including params.maxMultiqcEmailFileSize)
    // On success try attach the multiqc report
    def mqc_report = null
    try {
        if (workflow.success) {
            mqc_report = multiqc_report.getVal()
            if (mqc_report.getClass() == ArrayList){
                log.warn "[nf-core/sarek] Found multiple reports from process 'multiqc', will use only one"
                mqc_report = mqc_report[0]
            }
        }
    } catch (all) {
        log.warn "[nf-core/sarek] Could not attach MultiQC report to summary email"
    }

    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [ email: params.email, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir", mqcFile: mqc_report, mqcMaxSize: params.maxMultiqcEmailFileSize.toBytes() ]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (params.email) {
        try {
          if ( params.plaintext_email ){ throw GroovyException('Send plaintext e-mail, not HTML') }
          // Try to send HTML e-mail using sendmail
          [ 'sendmail', '-t' ].execute() << sendmail_html
          log.info "[nf-core/sarek] Sent summary e-mail to $params.email (sendmail)"
        } catch (all) {
          // Catch failures and try with plaintext
          [ 'mail', '-s', subject, params.email ].execute() << email_txt
          log.info "[nf-core/sarek] Sent summary e-mail to $params.email (mail)"
        }
    }

    // Write summary e-mail HTML to a file
    def output_d = new File( "${params.outdir}/pipeline_info/" )
    if ( !output_d.exists() ) {
      output_d.mkdirs()
    }
    def output_hf = new File( output_d, "pipeline_report.html" )
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File( output_d, "pipeline_report.txt" )
    output_tf.withWriter { w -> w << email_txt }

    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_red = params.monochrome_logs ? '' : "\033[0;31m";

    if (workflow.stats.ignoredCountFmt > 0 && workflow.success) {
      log.info "${c_purple}Warning, pipeline completed, but with errored process(es) ${c_reset}"
      log.info "${c_red}Number of ignored errored process(es) : ${workflow.stats.ignoredCountFmt} ${c_reset}"
      log.info "${c_green}Number of successfully ran process(es) : ${workflow.stats.succeedCountFmt} ${c_reset}"
    }

    if (workflow.success){
        log.info "${c_purple}[nf-core/sarek]${c_green} Pipeline completed successfully${c_reset}"
    } else {
        checkHostname()
        log.info "${c_purple}[nf-core/sarek]${c_red} Pipeline completed with errors${c_reset}"
    }

}

def nfcoreHeader(){
    // Log colors ANSI codes
    c_black  = params.monochrome_logs ? '' : "\033[0;30m";
    c_blue   = params.monochrome_logs ? '' : "\033[0;34m";
    c_cyan   = params.monochrome_logs ? '' : "\033[0;36m";
    c_dim    = params.monochrome_logs ? '' : "\033[2m";
    c_green  = params.monochrome_logs ? '' : "\033[0;32m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_reset  = params.monochrome_logs ? '' : "\033[0m";
    c_white  = params.monochrome_logs ? '' : "\033[0;37m";
    c_yellow = params.monochrome_logs ? '' : "\033[0;33m";

    return """    ${c_dim}----------------------------------------------------${c_reset}
                                            ${c_green},--.${c_black}/${c_green},-.${c_reset}
    ${c_blue}        ___     __   __   __   ___     ${c_green}/,-._.--~\'${c_reset}
    ${c_blue}  |\\ | |__  __ /  ` /  \\ |__) |__         ${c_yellow}}  {${c_reset}
    ${c_blue}  | \\| |       \\__, \\__/ |  \\ |___     ${c_green}\\`-._,-`-,${c_reset}
                                            ${c_green}`._,._,\'${c_reset}
    ${c_black}       ____      ${c_blue}  _____               _ ${c_reset}
    ${c_black}     .' ${c_green}_${c_black}  `.    ${c_blue} / ____|             | | ${c_reset}
    ${c_black}    /  ${c_green}|\\${c_white}`-_${c_black} \\ ${c_blue}  | (___  ___  _ __ __ | | __ ${c_reset}
    ${c_black}   |   ${c_green}| \\  ${c_white}`-${c_black}| ${c_blue}  \\___ \\/__ \\| ´__/ _\\| |/ / ${c_reset}
    ${c_black}    \\ ${c_green}|   \\  ${c_black}/ ${c_blue}   ____) | __ | | |  __|   < ${c_reset}
    ${c_black}     `${c_green}|${c_black}____${c_green}\\${c_black}'   ${c_blue} |_____/\\____|_|  \\__/|_|\\_\\ ${c_reset}

    ${c_purple}  nf-core/sarek v${workflow.manifest.version}${c_reset}
    ${c_dim}----------------------------------------------------${c_reset}
    """.stripIndent()
}

def checkHostname(){
    def c_reset = params.monochrome_logs ? '' : "\033[0m"
    def c_white = params.monochrome_logs ? '' : "\033[0;37m"
    def c_red = params.monochrome_logs ? '' : "\033[1;91m"
    def c_yellow_bold = params.monochrome_logs ? '' : "\033[1;93m"
    if (params.hostnames){
        def hostname = "hostname".execute().text.trim()
        params.hostnames.each { prof, hnames ->
            hnames.each { hname ->
                if (hostname.contains(hname) && !workflow.profile.contains(prof)){
                    log.error "====================================================\n" +
                            "  ${c_red}WARNING!${c_reset} You are running with `-profile $workflow.profile`\n" +
                            "  but your machine hostname is ${c_white}'$hostname'${c_reset}\n" +
                            "  ${c_yellow_bold}It's highly recommended that you use `-profile $prof${c_reset}`\n" +
                            "============================================================"
                }
            }
        }
    }
}

/*
========================================================================================
                         sarek functions
========================================================================================
*/

// Check if a row has the expected number of item
def checkNumberOfItem(row, number) {
  if (row.size() != number) exit 1, "Malformed row in TSV file: ${row}, see --help for more information"
  return true
}

// Check parameter existence
def checkParameterExistence(it, list) {
  if (!list.contains(it)) {
    println("Unknown parameter: ${it}")
    return false
  }
  return true
}

// Compare each parameter with a list of parameters
def checkParameterList(list, realList) {
  return list.every{ checkParameterExistence(it, realList) }
}

// Check if params.item exists and return params.genomes[params.genome].item otherwise
def checkParamReturnFile(item) {
  params."${item}" = params.genomes[params.genome]."${item}"
  return file(params."${item}")
}

// Loop through all the references files to check their existence
def checkRefExistence(referenceFile, fileToCheck) {
  if (fileToCheck instanceof List) return fileToCheck.every{ checkRefExistence(referenceFile, it) }
  def f = file(fileToCheck)
  // this is an expanded wildcard: we can assume all files exist
  if (f instanceof List && f.size() > 0) return true
  else if (!f.exists()) {
    println  "Missing references: ${referenceFile} ${fileToCheck}"
    return false
  }
  return true
}

// Loop through all the references files to check their existence
def checkReferenceMap(referenceMap) {
  referenceMap.every {
    referenceFile, fileToCheck ->
    checkRefExistence(referenceFile, fileToCheck)
  }
}

// Define map of reference depending of tools and step
def defineReferenceMap(step, tools) {
  def referenceMap =
  [
    'genomeDict'       : checkParamReturnFile("genomeDict"),
    'genomeFile'       : checkParamReturnFile("genomeFile"),
    'genomeIndex'      : checkParamReturnFile("genomeIndex"),
    'intervals'        : checkParamReturnFile("intervals")
  ]
  if ('mapping' in step) {
    referenceMap.putAll(
      'bwaIndex'         : checkParamReturnFile("bwaIndex"),
      'knownIndels'      : checkParamReturnFile("knownIndels"),
      'knownIndelsIndex' : checkParamReturnFile("knownIndelsIndex")
    )
  }
  if ('ascat' in tools) {
    referenceMap.putAll(
      'acLoci'           : checkParamReturnFile("acLoci"),
      'acLociGC'         : checkParamReturnFile("acLociGC")
    )
  }
  if ('mapping' in step || 'mutect2' in tools) {
    referenceMap.putAll(
      'dbsnp'            : checkParamReturnFile("dbsnp"),
      'dbsnpIndex'       : checkParamReturnFile("dbsnpIndex")
    )
  }
  return referenceMap
}

// Define list of available step
def defineStepList() {
  return [
    'mapping',
    'recalibrate',
    'variantcalling',
    'annotate'
  ]
}

// Define list of available tools
def defineToolList() {
  return [
    'ascat',
    'freebayes',
    'haplotypecaller',
    'manta',
    'mutect2',
    'strelka'
  ]
}

 // Create a channel of germline FASTQs from a directory pattern: "my_samples/*/"
 // All FASTQ files in subdirectories are collected and emitted;
 // they must have _R1_ and _R2_ in their names.
def extractFastqFromDir(pattern) {
  def fastq = Channel.create()
  // a temporary channel does all the work
  Channel
    .fromPath(pattern, type: 'dir')
    .ifEmpty { error "No directories found matching pattern '${pattern}'" }
    .subscribe onNext: { sampleDir ->
      // the last name of the sampleDir is assumed to be a unique sample id
      sampleId = sampleDir.getFileName().toString()

      for (path1 in file("${sampleDir}/**_R1_*.fastq.gz")) {
        assert path1.getName().contains('_R1_')
        path2 = file(path1.toString().replace('_R1_', '_R2_'))
        if (!path2.exists()) error "Path '${path2}' not found"
        (flowcell, lane) = flowcellLaneFromFastq(path1)
        patient = sampleId
        gender = 'ZZ'  // unused
        status = 0  // normal (not tumor)
        rgId = "${flowcell}.${sampleId}.${lane}"
        result = [patient, gender, status, sampleId, rgId, path1, path2]
        fastq.bind(result)
      }
  }, onComplete: { fastq.close() }
  fastq
}

// Extract gender from Channel as it's only used for CNVs
def extractGenders(channel) {
  def genders = [:]
  channel = channel.map{ it ->
    def idPatient = it[0]
    def gender = it[1]
    genders[idPatient] = gender
    [idPatient] + it[2..-1]
  }
  [genders, channel]
}

// Channeling the TSV file containing FASTQ or BAM
// Format is: "subject gender status sample lane fastq1 fastq2"
// or: "subject gender status sample lane bam"
def extractSample(tsvFile) {
  Channel.from(tsvFile)
  .splitCsv(sep: '\t')
  .map { row ->
    def idPatient  = row[0]
    def gender     = row[1]
    def status     = returnStatus(row[2].toInteger())
    def idSample   = row[3]
    def idRun      = row[4]
    def file1      = returnFile(row[5])
    def file2      = file("null")
    if (hasExtension(file1,"fastq.gz") || hasExtension(file1,"fq.gz")) {
      checkNumberOfItem(row, 7)
      file2 = returnFile(row[6])
      if (!hasExtension(file2,"fastq.gz") && !hasExtension(file2,"fq.gz")) exit 1, "File: ${file2} has the wrong extension. See --help for more information"
    }
    else if (hasExtension(file1,"bam")) checkNumberOfItem(row, 6)
    else "No recognisable extention for input file: ${file1}"

    [idPatient, gender, status, idSample, idRun, file1, file2]
  }
}

// Channeling the TSV file containing Recalibration Tables.
// Format is: "subject gender status sample bam bai recalTables"
def extractRecal(tsvFile) {
  Channel.from(tsvFile)
    .splitCsv(sep: '\t')
    .map { row ->
    checkNumberOfItem(row, 7)
    def idPatient  = row[0]
    def gender     = row[1]
    def status     = returnStatus(row[2].toInteger())
    def idSample   = row[3]
    def bamFile    = returnFile(row[4])
    def baiFile    = returnFile(row[5])
    def recalTable = returnFile(row[6])

    if (!hasExtension(bamFile,"bam")) exit 1, "File: ${bamFile} has the wrong extension. See --help for more information"
    if (!hasExtension(baiFile,"bai")) exit 1, "File: ${baiFile} has the wrong extension. See --help for more information"
    if (!hasExtension(recalTable,"recal.table")) exit 1, "File: ${recalTable} has the wrong extension. See --help for more information"

    [ idPatient, gender, status, idSample, bamFile, baiFile, recalTable ]
  }
}

// Check file extension
def hasExtension(it, extension) {
  it.toString().toLowerCase().endsWith(extension.toLowerCase())
}

// Return file if it exists
def returnFile(it) {
  if (!file(it).exists()) exit 1, "Missing file in TSV file: ${it}, see --help for more information"
  return file(it)
}

// Return status [0,1]
// 0 == Normal, 1 == Tumor
def returnStatus(it) {
  if (!(it in [0, 1])) exit 1, "Status is not recognized in TSV file: ${it}, see --help for more information"
  return it
}
