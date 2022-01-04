// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from './functions'

params.options = [:]
options        = initOptions(params.options)

process SAMTOOLS_INDEX {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), meta:meta, publish_by_meta:['id']) }

    conda (params.enable_conda ? "bioconda::samtools=1.12" : null)
    if (workflow.containerEngine == 'singularity' && !params.singularity_pull_docker_container) {
        container "https://depot.galaxyproject.org/singularity/samtools:1.12--hd5e65b6_0"
    } else {
        container "quay.io/biocontainers/samtools:1.12--hd5e65b6_0"
    }

    input:
    tuple val(meta), path(input)

    output:
    tuple val(meta), path("*.bam", includeInputs:true), path("*.bai")  , optional:true, emit: bam_bai
    tuple val(meta), path("*.bam", includeInputs:true), path("*.csi")  , optional:true, emit: bam_csi
    tuple val(meta), path("*.cram", includeInputs:true), path("*.crai"), optional:true, emit: cram_crai
    path  "*.version.txt"                                                             , emit: version

    script:
    def software = getSoftwareName(task.process)
    """
    samtools index $options.args $input
    echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//' > ${software}.version.txt
    """
}
