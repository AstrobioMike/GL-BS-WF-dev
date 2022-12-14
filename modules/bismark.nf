/*
 * Processes related to bismark processing.
 */

process GEN_BISMARK_REF {

    publishDir "./", mode: 'link'

    input:
        path( input_ref_fasta )

    output:
        path( params.bismark_index_dir ), emit: ch_bismark_index_dir

    script:

        """
        mkdir -p ${params.bismark_index_dir}

        # copying ref fasta in there so everything exists with the bismark index dir (required by bismark)
        cp ${input_ref_fasta} ${params.bismark_index_dir}

        # making index
        bismark_genome_preparation --bowtie2 --parallel ${params.bismark_index_creation_threads} ${params.bismark_index_dir} > bismark-genome-preparation-output.txt 2>&1

        # moving log file into bismark dir since i can't figure out how to do it with publishDirs above
        mv bismark-genome-preparation-output.txt ${params.bismark_index_dir}
        """        

}


process ALIGN {

    tag "On: $meta.id"

    // only keeping sorted bams, so blocking this publishDir out for now
    // publishDir params.bismark_alignments_dir, mode: 'link', pattern: "${ meta.id }_trimmed_bismark_*.bam"

    input:
        tuple val(meta), path(reads), path( bismark_index_dir )

    output:
        tuple val(meta), path("${ meta.id }_trimmed_bismark_*.bam"), emit: bams
        tuple val(meta), path("${ meta.id }_trimmed_bismark_*_report.txt"), emit: reports

    script:

        non_directional = params.non_directional ? '--non_directional' : ''
        fastq_files = params.single_end ? reads : "-1 ${reads[0]} -2 ${reads[1]}"

        """
        bismark --bam --non_bs_mm -p ${params.bismark_align_threads} --genome ${bismark_index_dir} ${non_directional} ${fastq_files} 
        """

}


process DEDUPLICATE {

    tag "On: $meta.id"

    publishDir params.bismark_alignments_dir, mode: 'link', pattern: "${ meta.id }_trimmed_bismark_*.bam"

    input:
        tuple val(meta), path(bam_file)

    output:
        tuple val(meta), path("${ meta.id }_trimmed_bismark_*.bam"), emit: bams
        tuple val(meta), path("${ meta.id }*_report.txt"), emit: reports

    script:

        """
        deduplicate_bismark ${bam_file}
        """

}


process EXTRACT_METHYLATION_CALLS {

    tag "On: $meta.id"

    publishDir params.bismark_methylation_calls_dir, mode: 'link', pattern: "*.gz"
    publishDir params.bismark_methylation_calls_dir, mode: 'link', pattern: "*M-bias.txt"

    input:
        tuple val(meta), path(bam_file)

    output:
        tuple val(meta), path("${ meta.id }*.cov.gz"), emit: covs
        tuple val(meta), path("${ meta.id }*.bedGraph.gz"), emit: beds
        tuple val(meta), path("*${ meta.id }*.txt.gz"), emit: contexts
        tuple val(meta), path("${ meta.id }*.M-bias.txt"), emit: biases
        tuple val(meta), path("${ meta.id }*_report.txt"), emit: reports

    script:

        additional_args = params.single_end ? "" : "--ignore_r2 2 --ignore_3prime_r2 2"

        """
        bismark_methylation_extractor --bedGraph --gzip --comprehensive ${additional_args} ${bam_file}
        """

}


process GEN_BISMARK_SAMPLE_REPORT {

    tag "On: $meta"

    publishDir params.individual_sample_reports, mode: 'link', pattern: "*.html"

    input:
        tuple val(meta), path(alignment_report), path(meth_calls_report), path(m_bias_report), file(dedupe_report)

    output:
        tuple val(meta), path("${ meta.id }*_report.html"), emit: reports

    script:

        additional_args = params.rrbs ? "" : "--dedup_report ${dedupe_report}"

        """
        bismark2report --alignment_report ${alignment_report} --splitting_report ${meth_calls_report} --mbias_report ${m_bias_report} ${additional_args}
        """

}


process GEN_BISMARK_SUMMARY {

    publishDir params.bismark_summary_dir, mode: 'link', pattern: "bismark_summary_report.*"

    input:
        file(all_bams_and_reports)

    output:
        tuple path("bismark_summary_report.html"), path("bismark_summary_report.txt"), emit: reports

    script:

        """
        bismark2summary
        """

}
