// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from './functions'

params.options = [:]
options        = initOptions(params.options)

process CREATE_INTERVALS_BED {
    tag "$intervals"
    label 'process_medium'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), meta:[:], publish_by_meta:[]) }

    conda (params.enable_conda ? "anaconda::gawk=5.1.0" : null)
    if (workflow.containerEngine == 'singularity' && !params.singularity_pull_docker_container) {
        container "https://depot.galaxyproject.org/singularity/gawk:5.1.0"
    } else {
        container "quay.io/biocontainers/gawk:5.1.0"
    }

    input:
    path intervals

    output:
    path ('*.bed')

    script:
    // If the interval file is BED format, the fifth column is interpreted to
    // contain runtime estimates, which is then used to combine short-running jobs
    if (intervals.toString().toLowerCase().endsWith("bed"))
        """
        awk -vFS="\t" '{
            t = \$5  # runtime estimate
                if (t == "") {
                    # no runtime estimate in this row, assume default value
                    t = (\$3 - \$2) / ${params.nucleotides_per_second}
                }
                if (name == "" || (chunk > 600 && (chunk + t) > longest * 1.05)) {
                    # start a new chunk
                    name = sprintf("%s_%d-%d.bed", \$1, \$2+1, \$3)
                    chunk = 0
                    longest = 0
                }
                if (t > longest)
                    longest = t
                chunk += t
                print \$0 > name
        }' ${intervals}
        """
    else if (intervals.toString().toLowerCase().endsWith("interval_list"))
        """
        grep -v '^@' ${intervals} | awk -vFS="\t" '{
            name = sprintf("%s_%d-%d", \$1, \$2, \$3);
            printf("%s\\t%d\\t%d\\n", \$1, \$2-1, \$3) > name ".bed"
        }'
        """
    else
        """
        awk -vFS="[:-]" '{
            name = sprintf("%s_%d-%d", \$1, \$2, \$3);
            printf("%s\\t%d\\t%d\\n", \$1, \$2-1, \$3) > name ".bed"
        }' ${intervals}
        """
}
