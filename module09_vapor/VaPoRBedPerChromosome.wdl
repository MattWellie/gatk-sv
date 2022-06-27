##########################################################################################

## Github commit: talkowski-lab/gatk-sv-v1:<ENTER HASH HERE IN FIRECLOUD>

##########################################################################################

## Copyright Broad Institute, 2020
## 
## This WDL pipeline implements Duphold 
##
##
## LICENSING : 
## This script is released under the WDL source code license (BSD-3) (see LICENSE in 
## https://github.com/broadinstitute/wdl). Note however that the programs it calls may 
## be subject to different licenses. Users are responsible for checking that they are
## authorized to run all programs before running this script. Please see the docker 
## page at https://hub.docker.com/r/broadinstitute/genomes-in-the-cloud/ for detailed
## licensing information pertaining to the included programs.

version 1.0

import "Structs.wdl"
import "TasksBenchmark.wdl" as mini_tasks
workflow VaPoRBedPerChromosome{
    input{
        String prefix
        String sample
        String bam_or_cram_file
        String bam_or_cram_index
        File? bed_file
        File ref_fasta
        File ref_fai
        File ref_dict
        String contig
        Int min_shard_size
        String vapor_docker
        String sv_base_mini_docker
        String sv_pipeline_docker
        RuntimeAttr? runtime_attr_vapor 
        RuntimeAttr? runtime_attr_bcf2vcf
        RuntimeAttr? runtime_attr_vcf2bed
        RuntimeAttr? runtime_attr_SplitVcf
        RuntimeAttr? runtime_attr_ConcatBeds
    }

    call mini_tasks.SplitBed as SplitBed{
      input:
        contig = contig,
        bed_file = bed_file,
        sv_pipeline_docker = sv_pipeline_docker,
        runtime_attr_override=runtime_attr_SplitVcf
    }
    
    call mini_tasks.bed2vapor as bed2vapor{
      input:
        prefix = prefix,
        sample = sample,
        bed_file = SplitBed.contig_bed,
        min_shard_size = min_shard_size,
        sv_pipeline_docker = sv_pipeline_docker,
        runtime_attr_override = runtime_attr_vcf2bed
    }

    scatter (vapor_bed in bed2vapor.vapor_beds){
        call RunVaPoRWithCram as RunVaPoR{
          input:
            prefix = prefix,
            contig = contig,
            bam_or_cram_file=bam_or_cram_file,
            bam_or_cram_index=bam_or_cram_index,
            bed = vapor_bed,
            ref_fasta = ref_fasta,
            ref_fai = ref_fai,
            ref_dict = ref_dict,
            vapor_docker = vapor_docker,
            runtime_attr_override = runtime_attr_vapor
        }
    }

    call mini_tasks.ConcatVaPoR as concat_vapor{
        input:
            shard_plots = RunVaPoR.vapor_plot,
            prefix=prefix,
            sv_base_mini_docker=sv_base_mini_docker,
            runtime_attr_override=runtime_attr_ConcatBeds
    }

    call mini_tasks.ConcatVaPoRBeds as concat_beds{
        input:
            shard_bed_files=RunVaPoR.vapor,
            prefix = prefix,
            sv_base_mini_docker = sv_base_mini_docker,
            runtime_attr_override=runtime_attr_ConcatBeds
    }

    output{
        File bed = concat_beds.merged_bed_file
        File plots = concat_vapor.merged_bed_plot
    }
}

task RunVaPoRWithCram{
  input{
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
    preemptible_tries: 0,
    max_retries: 1
  }

  RuntimeAttr runtime_attr = select_first([runtime_attr_override, default_attr])
  Float mem_gb = select_first([runtime_attr.mem_gb, default_attr.mem_gb])
  Int java_mem_mb = ceil(mem_gb * 1000 * 0.8)

  output {
    File vapor = "~{prefix}.~{contig}.vapor.gz"
    File vapor_plot = "~{prefix}.~{contig}.tar.gz"
  }


  command <<<

    set -Eeuo pipefail

    #localize cram files
    export GCS_OAUTH_TOKEN=`gcloud auth application-default print-access-token`   

    start=$(head -1 ~{bed} | awk '{print $2-1000}')
    end=$(tail -1 ~{bed} | awk '{print $3+1000}')

    samtools view -h -o ~{contig}.bam ~{bam_or_cram_file} ~{contig}:${start}-${end}
    samtools index ~{contig}.bam
  
    #run vapor
    mkdir ~{prefix}.~{contig}

    vapor bed \
      --sv-input ~{bed} \
      --output-path ~{prefix}.~{contig} \
      --output-file ~{prefix}.~{contig}.vapor \
      --reference ~{ref_fasta} \
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









