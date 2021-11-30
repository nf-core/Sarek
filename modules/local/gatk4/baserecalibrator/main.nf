process GATK4_BASERECALIBRATOR {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), meta:meta, publish_by_meta:['id']) }

    conda (params.enable_conda ? "bioconda::gatk4=4.2.0.0" : null)
    if (workflow.containerEngine == 'singularity' && !params.singularity_pull_docker_container) {
        container "https://depot.galaxyproject.org/singularity/gatk4:4.2.0.0--0"
    } else {
        container "quay.io/biocontainers/gatk4:4.2.0.0--0"
    }

    input:
    tuple val(meta), path(cram), path(crai), path(intervalsBed)
    path fasta
    path fai
    path dict
    path knownSites
    path knownSites_tbi

    output:
    tuple val(meta), path("*.table"), emit: table
    path "versions.yml"             , emit: versions

    script:
    def software = getSoftwareName(task.process)
    def prefix   = options.suffix ? "${meta.id}${options.suffix}" : "${meta.id}"
    def intervalsCommand = intervalsBed ? "-L ${intervalsBed}" : ""
    def sitesCommand = knownSites.collect{"--known-sites ${it}"}.join(' ')

    if (!task.memory) {
        log.info '[GATK BaseRecalibrator] Available memory not known - defaulting to 3GB. Specify process memory requirements to change this.'
    } else {
        avail_mem = task.memory.giga
    }
    """
    gatk BaseRecalibrator  \
        -R $fasta \
        -I $cram \
        $sitesCommand \
        $intervalsCommand \
        --tmp-dir . \
        $options.args \
        -O ${prefix}.table

    cat <<-END_VERSIONS > versions.yml
    ${getProcessName(task.process)}:
        ${getSoftwareName(task.process)}: \$(echo \$(gatk --version 2>&1) | sed 's/^.*(GATK) v//; s/ .*\$//')
    END_VERSIONS
    """
}
