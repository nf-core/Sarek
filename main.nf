#!/usr/bin/env nextflow

/*
========================================================================================
    nf-core/sarek
========================================================================================
    Started March 2016.
    Ported to nf-core May 2019.
    Ported to DSL 2 July 2020.
----------------------------------------------------------------------------------------
    nf-core/sarek:
        An open-source analysis pipeline to detect germline or somatic variants
        from whole genome or targeted sequencing
----------------------------------------------------------------------------------------
    @Website
    https://nf-co.re/sarek
----------------------------------------------------------------------------------------
    @Documentation
    https://nf-co.re/sarek/usage
----------------------------------------------------------------------------------------
    @Github
    https://github.com/nf-core/sarek
----------------------------------------------------------------------------------------
    @Slack
    https://nfcore.slack.com/channels/sarek
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl = 2

/*
========================================================================================
    GENOME PARAMETER VALUES
========================================================================================
*/

params.ac_loci               = WorkflowMain.getGenomeAttribute(params, 'ac_loci')
params.ac_loci_gc            = WorkflowMain.getGenomeAttribute(params, 'ac_loci_gc')
params.bwa                   = WorkflowMain.getGenomeAttribute(params, 'bwa')
params.chr_dir               = WorkflowMain.getGenomeAttribute(params, 'chr_dir')
params.chr_length            = WorkflowMain.getGenomeAttribute(params, 'chr_length')
params.dbsnp                 = WorkflowMain.getGenomeAttribute(params, 'dbsnp')
params.dbsnp_tbi             = WorkflowMain.getGenomeAttribute(params, 'dbsnp_tbi')
params.dict                  = WorkflowMain.getGenomeAttribute(params, 'dict')
params.fasta                 = WorkflowMain.getGenomeAttribute(params, 'fasta')
params.fasta_fai             = WorkflowMain.getGenomeAttribute(params, 'fasta_fai')
params.germline_resource     = WorkflowMain.getGenomeAttribute(params, 'germline_resource')
params.germline_resource_tbi = WorkflowMain.getGenomeAttribute(params, 'germline_resource_tbi')
params.intervals             = WorkflowMain.getGenomeAttribute(params, 'intervals')
params.known_indels          = WorkflowMain.getGenomeAttribute(params, 'known_indels')
params.known_indels_tbi      = WorkflowMain.getGenomeAttribute(params, 'known_indels_tbi')
params.mappability           = WorkflowMain.getGenomeAttribute(params, 'mappability')
params.snpeff_db             = WorkflowMain.getGenomeAttribute(params, 'snpeff_db')
params.vep_cache_version     = WorkflowMain.getGenomeAttribute(params, 'vep_cache_version')
params.vep_genome            = WorkflowMain.getGenomeAttribute(params, 'vep_genome')
params.vep_species           = WorkflowMain.getGenomeAttribute(params, 'vep_species')

/*
========================================================================================
    VALIDATE & PRINT PARAMETER SUMMARY
========================================================================================
*/

WorkflowMain.initialise(workflow, params, log)

/*
========================================================================================
    NAMED WORKFLOW FOR PIPELINE
========================================================================================
*/

include { SAREK } from './workflows/sarek'

// WORKFLOW: Run main nf-core/sarek analysis pipeline
workflow NFCORE_SAREK {
    SAREK ()
}

/*
========================================================================================
    RUN ALL WORKFLOWS
========================================================================================
*/

// WORKFLOW: Execute a single named workflow for the pipeline
// See: https://github.com/nf-core/rnaseq/issues/619
workflow {
    NFCORE_SAREK ()
}
