version 1.0

import "Structs.wdl"
import "VaPoR.wdl" as vapor_bed

workflow VaPoRBatch {
  input {
    Array[String] samples
    Array[File] bam_or_cram_files
    Array[File] bam_or_cram_indexes
    File bed_file  # Multi-sample bed file, generated from MainVcfQc

    File ref_fasta
    File ref_fai
    File ref_dict
    File contigs

    String vapor_docker
    String sv_base_mini_docker
    String sv_pipeline_docker

    RuntimeAttr? runtime_attr_vapor
    RuntimeAttr? runtime_attr_bcf2vcf
    RuntimeAttr? runtime_attr_vcf2bed
    RuntimeAttr? runtime_attr_split_vcf
    RuntimeAttr? runtime_attr_concat_beds
  }

  scatter (i in range(length(bam_or_cram_files))) {
    call vapor_bed.VaPoR {
      input:
        prefix = samples[i],
        bam_or_cram_file = bam_or_cram_files[i],
        bam_or_cram_index = bam_or_cram_indexes[i],
        bed_file = bed_file,
        sample_to_extract = samples[i],
        ref_fasta = ref_fasta,
        ref_fai = ref_fai,
        ref_dict = ref_dict,
        contigs = contigs,
        vapor_docker = vapor_docker,
        sv_base_mini_docker = sv_base_mini_docker,
        sv_pipeline_docker = sv_pipeline_docker,
        runtime_attr_vapor = runtime_attr_vapor,
        runtime_attr_bcf2vcf = runtime_attr_bcf2vcf,
        runtime_attr_vcf2bed = runtime_attr_vcf2bed,
        runtime_attr_split_vcf = runtime_attr_split_vcf,
        runtime_attr_concat_beds = runtime_attr_concat_beds
    }
  }
  output {
    Array[File] bed_out = VaPoR.bed
    Array[File] bed_plots = VaPoR.plots
  }
}


