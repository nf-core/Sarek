process GATK4_APPLYBQSR_SPARK {
    tag "$meta.id"
    label 'process_low'

    conda (params.enable_conda ? "bioconda::gatk4=4.2.3.0" : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/gatk4:4.2.3.0--hdfd78af_0' :
        'quay.io/biocontainers/gatk4:4.2.3.0--hdfd78af_0' }"

    input:
    tuple val(meta), path(cram), path(crai), path(bqsr_table), path(intervals_bed)
    path  fasta
    path  fasta_fai
    path  dict

    output:
    tuple val(meta), path("*.cram"), emit: cram
    path "versions.yml"            , emit: versions

    script:
    def args = task.ext.args  ?: ''
    def avail_mem = 3
    if (!task.memory) {
        log.info '[GATK ApplyBQSRSpark] Available memory not known - defaulting to 3GB. Specify process memory requirements to change this.'
    } else {
        avail_mem = task.memory.giga
    }
    def prefix = task.ext.suffix ? "${meta.id}${task.ext.suffix}" : "${meta.id}"
    def intervals_command = intervals_bed ? "-L ${intervals_bed}" : ""
    """
    gatk ApplyBQSRSpark \\
        -R $fasta \\
        -I $cram \\
        --bqsr-recal-file $bqsr_table \\
        $intervals_command \\
        --tmp-dir . \
        -O ${prefix}.cram \\
        $args \
        --spark-master local[${task.cpus}]

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        gatk4: \$(echo \$(gatk --version 2>&1) | sed 's/^.*(GATK) v//; s/ .*\$//')
    END_VERSIONS
    """
}
