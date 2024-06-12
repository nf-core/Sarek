#!/usr/bin/env nextflow

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    nf-core/sarek
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Started March 2016.
    Ported to nf-core May 2019.
    Ported to DSL 2 July 2020.
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    nf-core/sarek:
        An open-source analysis pipeline to detect germline or somatic variants
        from whole genome or targeted sequencing
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/nf-core/sarek
    Website: https://nf-co.re/sarek
    Docs   : https://nf-co.re/sarek/usage
    Slack  : https://nfcore.slack.com/channels/sarek
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

nextflow.enable.dsl = 2
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    GENOME PARAMETER VALUES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
params.ascat_alleles           = getGenomeAttribute('ascat_alleles')
params.ascat_genome            = getGenomeAttribute('ascat_genome')
params.ascat_loci              = getGenomeAttribute('ascat_loci')
params.ascat_loci_gc           = getGenomeAttribute('ascat_loci_gc')
params.ascat_loci_rt           = getGenomeAttribute('ascat_loci_rt')
params.bwa                     = getGenomeAttribute('bwa')
params.bwamem2                 = getGenomeAttribute('bwamem2')
params.cf_chrom_len            = getGenomeAttribute('cf_chrom_len')
params.chr_dir                 = getGenomeAttribute('chr_dir')
params.dbsnp                   = getGenomeAttribute('dbsnp')
params.dbsnp_tbi               = getGenomeAttribute('dbsnp_tbi')
params.dbsnp_vqsr              = getGenomeAttribute('dbsnp_vqsr')
params.dict                    = getGenomeAttribute('dict')
params.dragmap                 = getGenomeAttribute('dragmap')
params.fasta                   = getGenomeAttribute('fasta')
params.fasta_fai               = getGenomeAttribute('fasta_fai')
params.germline_resource       = getGenomeAttribute('germline_resource')
params.germline_resource_tbi   = getGenomeAttribute('germline_resource_tbi')
params.intervals               = getGenomeAttribute('intervals')
params.known_indels            = getGenomeAttribute('known_indels')
params.known_indels_tbi        = getGenomeAttribute('known_indels_tbi')
params.known_indels_vqsr       = getGenomeAttribute('known_indels_vqsr')
params.known_snps              = getGenomeAttribute('known_snps')
params.known_snps_tbi          = getGenomeAttribute('known_snps_tbi')
params.known_snps_vqsr         = getGenomeAttribute('known_snps_vqsr')
params.mappability             = getGenomeAttribute('mappability')
params.ngscheckmate_bed        = getGenomeAttribute('ngscheckmate_bed')
params.pon                     = getGenomeAttribute('pon')
params.pon_tbi                 = getGenomeAttribute('pon_tbi')
params.sentieon_dnascope_model = getGenomeAttribute('sentieon_dnascope_model')
params.snpeff_db               = getGenomeAttribute('snpeff_db')
params.snpeff_genome           = getGenomeAttribute('snpeff_genome')
params.vep_cache_version       = getGenomeAttribute('vep_cache_version')
params.vep_genome              = getGenomeAttribute('vep_genome')
params.vep_species             = getGenomeAttribute('vep_species')

aligner = params.aligner

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { SAREK                           } from './workflows/sarek'
include { VARIANTANNOTATION               } from './workflows/variantannotation'
include { PREPARE_VARIANTANNOTATION       } from './subworkflows/local/prepare_variantannotation'
include { PIPELINE_COMPLETION             } from './subworkflows/local/utils_nfcore_sarek_pipeline'
include { PIPELINE_INITIALISATION         } from './subworkflows/local/utils_nfcore_sarek_pipeline'
include { PREPARE_GENOME                  } from './subworkflows/local/prepare_genome'
include { PREPARE_INTERVALS               } from './subworkflows/local/prepare_intervals'
include { PREPARE_REFERENCE_CNVKIT        } from './subworkflows/local/prepare_reference_cnvkit'
include { GATHER_REPORTS_VERSIONS         } from './subworkflows/local/utils_nfcore_sarek_pipeline'

// Initialize fasta file with meta map:
fasta = params.fasta ? Channel.fromPath(params.fasta).map{ it -> [ [id:it.baseName], it ] }.collect() : Channel.empty()

// Initialize file channels based on params, defined in the params.genomes[params.genome] scope
cf_chrom_len            = params.cf_chrom_len            ? Channel.fromPath(params.cf_chrom_len).collect()              : []
dbsnp                   = params.dbsnp                   ? Channel.fromPath(params.dbsnp).collect()                     : Channel.value([])
fasta_fai               = params.fasta_fai               ? Channel.fromPath(params.fasta_fai).collect()                 : Channel.empty()
germline_resource       = params.germline_resource       ? Channel.fromPath(params.germline_resource).collect()         : Channel.value([]) // Mutect2 does not require a germline resource, so set to optional input
known_indels            = params.known_indels            ? Channel.fromPath(params.known_indels).collect()              : Channel.value([])
known_snps              = params.known_snps              ? Channel.fromPath(params.known_snps).collect()                : Channel.value([])
mappability             = params.mappability             ? Channel.fromPath(params.mappability).collect()               : Channel.value([])
pon                     = params.pon                     ? Channel.fromPath(params.pon).collect()                       : Channel.value([]) // PON is optional for Mutect2 (but highly recommended)
sentieon_dnascope_model = params.sentieon_dnascope_model ? Channel.fromPath(params.sentieon_dnascope_model).collect()   : Channel.value([])

// Initialize value channels based on params, defined in the params.genomes[params.genome] scope
ascat_genome                = params.ascat_genome       ?:  Channel.empty()
dbsnp_vqsr                  = params.dbsnp_vqsr         ?   Channel.value(params.dbsnp_vqsr)        : Channel.empty()
known_indels_vqsr           = params.known_indels_vqsr  ?   Channel.value(params.known_indels_vqsr) : Channel.empty()
known_snps_vqsr             = params.known_snps_vqsr    ?   Channel.value(params.known_snps_vqsr)   : Channel.empty()
ngscheckmate_bed            = params.ngscheckmate_bed   ?   Channel.value(params.ngscheckmate_bed)  : Channel.empty()
snpeff_db                   = params.snpeff_db          ?:  Channel.empty()
vep_cache_version           = params.vep_cache_version  ?:  Channel.empty()
vep_genome                  = params.vep_genome         ?:  Channel.empty()
vep_species                 = params.vep_species        ?:  Channel.empty()

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOW FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// WORKFLOW: Run main nf-core/sarek analysis pipeline
workflow NFCORE_SAREK {
    take:
    samplesheet

    main:
    versions = Channel.empty()

    // build indexes if needed
    PREPARE_GENOME(
        params.ascat_alleles,
        params.ascat_loci,
        params.ascat_loci_gc,
        params.ascat_loci_rt,
        params.chr_dir,
        dbsnp,
        fasta,
        germline_resource,
        known_indels,
        known_snps,
        pon)

    // Gather built indices or get them from the params
    // Built from the fasta file:
    dict        = params.dict       ? Channel.fromPath(params.dict).map{ it -> [ [id:'dict'], it ] }.collect()
                                    : PREPARE_GENOME.out.dict
    fasta_fai   = params.fasta_fai  ? Channel.fromPath(params.fasta_fai).map{ it -> [ [id:'fai'], it ] }.collect()
                                    : PREPARE_GENOME.out.fasta_fai
    bwa         = params.bwa        ? Channel.fromPath(params.bwa).map{ it -> [ [id:'bwa'], it ] }.collect()
                                    : PREPARE_GENOME.out.bwa
    bwamem2     = params.bwamem2    ? Channel.fromPath(params.bwamem2).map{ it -> [ [id:'bwamem2'], it ] }.collect()
                                    : PREPARE_GENOME.out.bwamem2
    dragmap     = params.dragmap    ? Channel.fromPath(params.dragmap).map{ it -> [ [id:'dragmap'], it ] }.collect()
                                    : PREPARE_GENOME.out.hashtable

    // Gather index for mapping given the chosen aligner
    index_alignment = (aligner == "bwa-mem" || aligner == "sentieon-bwamem") ? bwa :
        aligner == "bwa-mem2" ? bwamem2 :
        dragmap

    // TODO: add a params for msisensorpro_scan
    msisensorpro_scan      = PREPARE_GENOME.out.msisensorpro_scan

    // For ASCAT, extracted from zip or tar.gz files
    allele_files           = PREPARE_GENOME.out.allele_files
    chr_files              = PREPARE_GENOME.out.chr_files
    gc_file                = PREPARE_GENOME.out.gc_file
    loci_files             = PREPARE_GENOME.out.loci_files
    rt_file                = PREPARE_GENOME.out.rt_file

    // Tabix indexed vcf files
    dbsnp_tbi                 = params.dbsnp                   ? params.dbsnp_tbi                ? Channel.fromPath(params.dbsnp_tbi).collect()                : PREPARE_GENOME.out.dbsnp_tbi                : Channel.value([])
    germline_resource_tbi     = params.germline_resource       ? params.germline_resource_tbi    ? Channel.fromPath(params.germline_resource_tbi).collect()    : PREPARE_GENOME.out.germline_resource_tbi    : [] //do not change to Channel.value([]), the check for its existence then fails for Getpileupsumamries
    known_indels_tbi          = params.known_indels            ? params.known_indels_tbi         ? Channel.fromPath(params.known_indels_tbi).collect()         : PREPARE_GENOME.out.known_indels_tbi         : Channel.value([])
    known_snps_tbi            = params.known_snps              ? params.known_snps_tbi           ? Channel.fromPath(params.known_snps_tbi).collect()           : PREPARE_GENOME.out.known_snps_tbi           : Channel.value([])
    pon_tbi                   = params.pon                     ? params.pon_tbi                  ? Channel.fromPath(params.pon_tbi).collect()                  : PREPARE_GENOME.out.pon_tbi                  : Channel.value([])

    // known_sites is made by grouping both the dbsnp and the known snps/indels resources
    // Which can either or both be optional
    known_sites_indels     = dbsnp.concat(known_indels).collect()
    known_sites_indels_tbi = dbsnp_tbi.concat(known_indels_tbi).collect()
    known_sites_snps       = dbsnp.concat(known_snps).collect()
    known_sites_snps_tbi   = dbsnp_tbi.concat(known_snps_tbi).collect()

    // Build intervals if needed
    PREPARE_INTERVALS(fasta_fai, params.intervals, params.no_intervals, params.nucleotides_per_second, params.outdir, params.step)

    // Intervals for speed up preprocessing/variant calling by spread/gather
    // [interval.bed] all intervals in one file
    intervals_bed_combined         = params.no_intervals ? Channel.value([]) : PREPARE_INTERVALS.out.intervals_bed_combined
    intervals_bed_gz_tbi_combined  = params.no_intervals ? Channel.value([]) : PREPARE_INTERVALS.out.intervals_bed_gz_tbi_combined
    intervals_bed_combined_for_variant_calling = PREPARE_INTERVALS.out.intervals_bed_combined

    // For QC during preprocessing, we don't need any intervals (MOSDEPTH doesn't take them for WGS)
    intervals_for_preprocessing = params.wes ?
        intervals_bed_combined.map{it -> [ [ id:it.baseName ], it ]}.collect() :
        Channel.value([ [ id:'null' ], [] ])
    intervals            = PREPARE_INTERVALS.out.intervals_bed        // [ interval, num_intervals ] multiple interval.bed files, divided by useful intervals for scatter/gather
    intervals_bed_gz_tbi = PREPARE_INTERVALS.out.intervals_bed_gz_tbi // [ interval_bed, tbi, num_intervals ] multiple interval.bed.gz/.tbi files, divided by useful intervals for scatter/gather
    intervals_and_num_intervals = intervals.map{ interval, num_intervals ->
        if ( num_intervals < 1 ) [ [], num_intervals ]
        else [ interval, num_intervals ]
    }
    intervals_bed_gz_tbi_and_num_intervals = intervals_bed_gz_tbi.map{ intervals, num_intervals ->
        if ( num_intervals < 1 ) [ [], [], num_intervals ]
        else [ intervals[0], intervals[1], num_intervals ]
    }
    if (params.tools && params.tools.split(',').contains('cnvkit')) {
        if (params.cnvkit_reference) {
            cnvkit_reference = Channel.fromPath(params.cnvkit_reference).collect()
        } else {
            PREPARE_REFERENCE_CNVKIT(fasta, intervals_bed_combined)
            cnvkit_reference = PREPARE_REFERENCE_CNVKIT.out.cnvkit_reference
            versions = versions.mix(PREPARE_REFERENCE_CNVKIT.out.versions)
        }
    } else {
        cnvkit_reference = Channel.value([])
    }
    // Gather used softwares versions
    versions = versions.mix(PREPARE_GENOME.out.versions)
    versions = versions.mix(PREPARE_INTERVALS.out.versions)

    //
    // WORKFLOW: Run pipeline
    //
    SAREK(samplesheet,
        allele_files,
        cf_chrom_len,
        chr_files,
        cnvkit_reference,
        dbsnp,
        dbsnp_tbi,
        dbsnp_vqsr,
        dict,
        fasta,
        fasta_fai,
        gc_file,
        germline_resource,
        germline_resource_tbi,
        index_alignment,
        intervals_and_num_intervals,
        intervals_bed_combined,
        intervals_bed_combined_for_variant_calling,
        intervals_bed_gz_tbi_and_num_intervals,
        intervals_bed_gz_tbi_combined,
        intervals_for_preprocessing,
        known_indels_vqsr,
        known_sites_indels,
        known_sites_indels_tbi,
        known_sites_snps,
        known_sites_snps_tbi,
        known_snps_vqsr,
        loci_files,
        mappability,
        msisensorpro_scan,
        ngscheckmate_bed,
        pon,
        pon_tbi,
        rt_file,
        sentieon_dnascope_model
    )

    // ANNOTATE
    vcf_to_annotate = Channel.empty()
    if (params.step == 'annotate') vcf_to_annotate = samplesheet
    else vcf_to_annotate = SAREK.out.vcf

    //
    // SUBWORKFLOW: Handle local or cloud annotation cache
    //     Or alternatevly download cache
    //     And index file if needed
    //
    PREPARE_VARIANTANNOTATION(
        params.fasta,
        (params.tools && (params.tools.split(',').contains("bcfann")) && params.bcftools_annotations),
        params.bcftools_annotations,
        params.bcftools_annotations_tbi,
        params.bcftools_header_lines,
        params.download_cache,
        "Please refer to https://nf-co.re/variantannotation/docs/usage/#how-to-customise-snpeff-and-vep-annotation for more information.",
        (params.tools && (params.tools.split(',').contains("snpeff") || params.tools.split(',').contains('merge'))),
        params.snpeff_cache,
        params.snpeff_genome,
        params.snpeff_db,
        (params.tools && (params.tools.split(',').contains("vep") || params.tools.split(',').contains('merge'))),
        params.vep_cache,
        params.vep_species,
        params.vep_cache_version,
        params.vep_include_fasta,
        params.vep_genome,
        params.vep_custom_args,
        params.dbnsfp,
        params.dbnsfp_tbi,
        params.spliceai_snv,
        params.spliceai_snv_tbi,
        params.spliceai_indel,
        params.spliceai_indel_tbi)

    //
    // WORKFLOW: Run main workflow
    //
    VARIANTANNOTATION(
        vcf_to_annotate,
        (params.tools && (params.tools.split(',').contains("bcfann"))),
        PREPARE_VARIANTANNOTATION.out.bcftools_annotations,
        PREPARE_VARIANTANNOTATION.out.bcftools_annotations_tbi,
        PREPARE_VARIANTANNOTATION.out.bcftools_header_lines,
        (params.tools && (params.tools.split(',').contains("snpeff") || params.tools.split(',').contains('merge'))),
        params.snpeff_genome ? "${params.snpeff_genome}.${params.snpeff_db}" : "${params.genome}.${params.snpeff_db}",
        PREPARE_VARIANTANNOTATION.out.snpeff_cache,
        (params.tools && (params.tools.split(',').contains("merge"))),
        (params.tools && (params.tools.split(',').contains("vep") || params.tools.split(',').contains('merge'))),
        PREPARE_VARIANTANNOTATION.out.vep_cache,
        params.vep_cache_version,
        PREPARE_VARIANTANNOTATION.out.vep_extra_files,
        PREPARE_VARIANTANNOTATION.out.vep_fasta,
        params.vep_genome,
        params.vep_species
    )

    emit:
    reports  = SAREK.out.reports.mix(VARIANTANNOTATION.out.reports)   // channel: [ path(reports) ]
    versions = SAREK.out.versions.mix(VARIANTANNOTATION.out.versions) // channel: [ path(versions.yml) ]
}
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    main:

    //
    // SUBWORKFLOW: Run initialisation tasks
    //
    PIPELINE_INITIALISATION(
        params.version,
        params.help,
        params.validate_params,
        params.monochrome_logs,
        args,
        params.outdir,
        params.input
    )

    //
    // WORKFLOW: Run main workflow
    //
    NFCORE_SAREK(PIPELINE_INITIALISATION.out.samplesheet)

    // GATHER REPORTS/VERSIONS AND RUN MULTIC

    if (params.skip_tools && (params.skip_tools.split(',').contains("multiqc"))) {
        GATHER_REPORTS_VERSIONS(
            params.outdir,
            params.multiqc_config,
            params.multiqc_logo,
            params.multiqc_methods_description,
            NFCORE_SAREK.out.versions,
            NFCORE_SAREK.out.reports
        )

        final_report = GATHER_REPORTS_VERSIONS.out.multiqc_report
    } else final_report = []

    //
    // SUBWORKFLOW: Run completion tasks
    //
    PIPELINE_COMPLETION(
        params.email,
        params.email_on_fail,
        params.plaintext_email,
        params.outdir,
        params.monochrome_logs,
        params.hook_url,
        final_report
    )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Get attribute from genome config file e.g. fasta
//

def getGenomeAttribute(attribute) {
    if (params.genomes && params.genome && params.genomes.containsKey(params.genome)) {
        if (params.genomes[ params.genome ].containsKey(attribute)) {
            return params.genomes[ params.genome ][ attribute ]
        }
    }
    return null
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
