version 1.0

import "Structs.wdl"
import "TasksBenchmark.wdl" as tasks10

workflow VaPoR {
  input {
    String prefix
    File bam_or_cram_file
    File bam_or_cram_index
    File bed_file
    String? sample_to_extract

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
    RuntimeAttr? runtime_attr_LocalizeCram
  }

  scatter ( contig in read_lines(contigs) ) {

    call tasks10.SplitBed as SplitBed {
      input:
        contig = contig,
        sample_to_extract = sample_to_extract,
        bed_file = bed_file,
        sv_pipeline_docker = sv_pipeline_docker,
        runtime_attr_override = runtime_attr_split_vcf
    }
    
    File contig_bed = SplitBed.contig_bed

    call RunVaPoRWithCram {
      input:
        prefix = prefix,
        contig = contig,
        bam_or_cram_file = bam_or_cram_file,
        bam_or_cram_index = bam_or_cram_index,
        bed = contig_bed,
        ref_fasta = ref_fasta,
        ref_fai = ref_fai,
        ref_dict = ref_dict,
        vapor_docker = vapor_docker,
        runtime_attr_override = runtime_attr_vapor
    }
  }

  call tasks10.ConcatVaPoR {
    input:
      shard_bed_files=RunVaPoRWithCram.vapor,
      shard_plots=RunVaPoRWithCram.vapor_plot,
      prefix=prefix,
      sv_base_mini_docker=sv_base_mini_docker,
      runtime_attr_override=runtime_attr_concat_beds
  }

  output {
    File bed = ConcatVaPoR.merged_bed_file
    File plots = ConcatVaPoR.merged_bed_plot
  }
}

task RunVaPoRWithCram {
  input {
    String prefix
    String contig
    String bam_or_cram_file
    String bam_or_cram_index
    File bed
    File ref_fasta
    File ref_fai
    File ref_dict
    String vapor_docker
    RuntimeAttr? runtime_attr_override
  }

  RuntimeAttr default_attr = object {
    cpu_cores: 1, 
    mem_gb: 15, 
    disk_gb: 30,
    boot_disk_gb: 10,
    preemptible_tries: 3,
    max_retries: 1
  }

  RuntimeAttr runtime_attr = select_first([runtime_attr_override, default_attr])
  Float mem_gb = select_first([runtime_attr.mem_gb, default_attr.mem_gb])
  Int java_mem_mb = ceil(mem_gb * 1000 * 0.8)

  output {
    #File local_bam = "~{contig}.bam"
    File vapor = "~{prefix}.~{contig}.vapor.gz"
    File vapor_plot = "~{prefix}.~{contig}.tar.gz"
  }

  command <<<

    set -Eeuo pipefail

    #localize cram files
    export GCS_OAUTH_TOKEN=`gcloud auth application-default print-access-token`   
    samtools view -h -o ~{contig}.bam ~{bam_or_cram_file} ~{contig}
    samtools index ~{contig}.bam
  
    #run vapor
    mkdir ~{prefix}.~{contig}

    vapor bed \
      --sv-input ~{bed} \
      --output-path ~{prefix}.~{contig} \
      --output-file ~{prefix}.~{contig}.vapor \
      --reference ~{ref_fasta} \
      --PB-supp 0 \
      --pacbio-input ~{contig}.bam

    tar -czf ~{prefix}.~{contig}.tar.gz ~{prefix}.~{contig}
    bgzip  ~{prefix}.~{contig}.vapor
  >>>
  runtime {
    cpu: select_first([runtime_attr.cpu_cores, default_attr.cpu_cores])
    memory: select_first([runtime_attr.mem_gb, default_attr.mem_gb]) + " GiB"
    disks: "local-disk " + select_first([runtime_attr.disk_gb, default_attr.disk_gb]) + " HDD"
    bootDiskSizeGb: select_first([runtime_attr.boot_disk_gb, default_attr.boot_disk_gb])
    docker: vapor_docker
    preemptible: select_first([runtime_attr.preemptible_tries, default_attr.preemptible_tries])
    maxRetries: select_first([runtime_attr.max_retries, default_attr.max_retries])
  }
}
