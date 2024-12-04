//
// MuSE tumor-normal variant calling
//
// For all modules here:
// A when clause condition is defined in the conf/modules.config to determine if the module should be run

include { MUSE_CALL } from '../../../modules/nf-core/muse/call/main'
include { MUSE_SUMP } from '../../../modules/nf-core/muse/sump/main'
include { SAMTOOLS_CONVERT as CRAM_TO_BAM_TUMOR } from '../../../modules/nf-core/samtools/convert/main'
include { SAMTOOLS_CONVERT as CRAM_TO_BAM_NORMAL } from '../../../modules/nf-core/samtools/convert/main'

workflow BAM_VARIANT_CALLING_SOMATIC_MUSE {
    take:
    cram          // channel: [mandatory] [ meta, normal_cram, normal_crai, tumor_cram, tumor_crai ]
    fasta         // channel: [mandatory] [ meta, fasta ]
    fai           // channel: [mandatory] [ meta, fai ]
    dbsnp         // channel: [optional] [ dbsnp ]
    dbsnp_tbi     // channel: [optional] [ dbsnp_tbi ]

    main:
    versions = Channel.empty()

    CRAM_TO_BAM_TUMOR(
        cram.map{ meta, normal_cram, normal_crai,tumor_cram, tumor_crai -> [ meta + [ tobam: 'tumor' ], tumor_cram, tumor_crai ] },
        fasta,
        fai
    )

    CRAM_TO_BAM_NORMAL(
        cram.map{ meta, normal_cram, normal_crai,tumor_cram, tumor_crai -> [ meta + [ tobam: 'normal' ], normal_cram, normal_crai ] },
        fasta,
        fai
    )

    ch_normal_bam = CRAM_TO_BAM_NORMAL.out.bam
    ch_normal_bai = CRAM_TO_BAM_NORMAL.out.bai
    ch_tumor_bam = CRAM_TO_BAM_TUMOR.out.bam
    ch_tumor_bai = CRAM_TO_BAM_TUMOR.out.bai

    // Combine normal BAM and BAI
    ch_normal = ch_normal_bam.join(ch_normal_bai, by: [0])  // Join by meta

    // Combine tumor BAM and BAI
    ch_tumor = ch_tumor_bam.join(ch_tumor_bai, by: [0])  // Join by meta

    // Combine normal and tumor data
    ch_combined = ch_normal.join(ch_tumor, by: [0])  // Join by meta

    // Rearrange the elements to match the desired output
    ch_bam = ch_combined.map { meta, normal_bam, normal_bai, tumor_bam, tumor_bai ->
        [meta, normal_bam, normal_bai, tumor_bam, tumor_bai]
    }

    MUSE_CALL(
        ch_bam,
        fasta
    )

    MUSE_SUMP(
        MUSE_CALL.out.txt,
        dbsnp.map{ it -> [ [ id:it.baseName ], it, dbsnp_tbi ] }
    )

    // Mix intervals and no_intervals channels together
    vcf = Channel.empty().mix(MUSE_SUMP.out.vcf)
        .map{ meta, vcf -> [ meta + [ variantcaller: 'muse' ], vcf ] }

    versions = versions.mix(CRAM_TO_BAM_NORMAL.out.versions)
    versions = versions.mix(CRAM_TO_BAM_TUMOR.out.versions)
    versions = versions.mix(MUSE_CALL.out.versions)
    versions = versions.mix(MUSE_SUMP.out.versions)

    emit:
    vcf
    versions
}
