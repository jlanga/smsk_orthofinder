rule busco_download:
    output: BUSCO + "{database}_odb9.tar.gz"
    params: "http://busco.ezlab.org/v2/datasets/{database}_odb9.tar.gz"
    conda: "busco.yml"
    log: BUSCO + "download_{database}_odb9.log"
    benchmark: BUSCO + "download_{database}_odb9.bmk"
    shell:
        "wget --continue {params} --output-document {output} 2> {log} 1>&2"

rule busco_extract:
    """
    Extract Busco database
    """
    input: rules.busco_download.output[0]
    output: directory(BUSCO + "{database}_odb9")
    log: BUSCO + "{database}_odb9.log"
    benchmark: BUSCO + "{database}_odb9.bmk"
    shell:
        """
        tar --extract --verbose --file {input} --directory {BUSCO} 2> {log} 1>&2
        """

rule busco_run:
    input:
        fasta = RAW + "{species}.pep",
        db_folder = rules.busco_extract.output[0]
    output: directory(BUSCO + "{species}_{database}")
    log: BUSCO + "{species}_{database}.log"
    benchmark: BUSCO + "{species}_{database}.bmk"
    threads: 4
    params:
        output_tag = "{species}_{database}"
    conda: "busco.yml"
    shell:
        """
        run_busco \
            --in {input.fasta} \
            --out {params.output_tag} \
            --lineage_path {input.db_folder} \
            --mode prot \
            --cpu {threads} \
        2> {log} 1>&2

        mv run_{params.output_tag} {output}
        """


rule busco_multiqc:
    input:
        expand(
            BUSCO + "{species}_{database}",
            species=SPECIES,
            database=features["busco_species"]
        ),
    output: BUSCO + "BUSCO_multiqc_report.html"
    log: BUSCO + "BUSCO_multiqc_report.log"
    benchmark: BUSCO + "BUSCO_multiqc_report.bmk"
    conda: "busco.yml"
    shell:
        "multiqc "
            "--title BUSCO "
            "--module busco "
            "--outdir {BUSCO} "
            "{BUSCO} "
        "2> {log} 1>&2"


rule busco:
    input:
        expand(
            BUSCO + "{species}_{database}",
            species=SPECIES,
            database=features["busco_species"]
        ),
        BUSCO + "BUSCO_multiqc_report.html"
    shell:
        "rm -rf tmp"
