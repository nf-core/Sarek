process SAMTOOLS_FASTQ {
    tag "$meta.id"
    label 'process_low'

    conda (params.enable_conda ? "bioconda::samtools=1.14" : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.14--hb421002_0' :
        'quay.io/biocontainers/samtools:1.14--hb421002_0' }"

    input:
    tuple val(meta), path(input)

    output:
    //TODO might be good to have ordered output of the fastq files, so we can
    // make sure the we get the right files
    tuple val(meta), path("*.fq.gz"), emit: reads
    path "versions.yml"             , emit: versions

    script:
    def args = task.ext.args ?: ''
    def args2 = task.ext.args ?: ''

    def prefix = task.ext.prefix ?: "${meta.id}"


    """
    samtools collate -O -@$task.cpus $args $input . |

    samtools \\
        fastq \\
        $args2 \\
        -@ $task.cpus \\
        -1 ${prefix}_1.fq.gz \\
        -2 ${prefix}_2.fq.gz \\
        -0 ${prefix}_other.fq.gz \\
        -s ${prefix}_singleton.fq.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
    END_VERSIONS
    """
}
