def get_models(wildcards):
    return params["selection"]["foreground_branches"][wildcards.group]["models"]


def get_species(wildcards):
    return params["selection"]["foreground_branches"][wildcards.group]["species"]

def get_min_foreground(wildcards):
    return params["selection"]["foreground_branches"][wildcards.group]["min_foreground"]

def get_min_background(wildcards):
    return params["selection"]["foreground_branches"][wildcards.group]["min_background"]

rule selection_trees_group:
    input:
        tree = TREE + "exabayes/ExaBayes.rooted.nwk",
        msa_folder = HOMOLOGS_REFINE2 + "maxalign",
    output:
        tree_folder = directory(SELECTION + "{group}/trees")
    log: SELECTION + "{group}/trees.log"
    benchmark: SELECTION + "{group}/trees.bmk"
    conda: "selection.yml"
    params:
        species = get_species,
        min_foreground = get_min_foreground,
        min_background = get_min_background
    shell:
        """
        python src/homologs/ete3_evol_prepare_folder.py \
            {input.tree} \
            {input.msa_folder} fa \
            {output.tree_folder} nwk \
            {params.species} \
            {params.min_foreground} \
            {params.min_background} \
        2> {log} 1>&2
        """


rule selection_trees:
    input:
        expand(
            SELECTION + "trees_{group}",
            group=params["selection"]["foreground_branches"]
        )


rule selection_ete3_group:
    input:
        msa_folder = HOMOLOGS_REFINE2 + "maxalign",
        tree_folder = SELECTION + "{group}/trees"
    output:
        ete3_folder = directory(SELECTION + "{group}/ete3"),
        tsv = SELECTION + "{group}/ete3.tsv"
    log: SELECTION + "{group}/ete3.log"
    benchmark: SELECTION + "{group}/ete3.bmk"
    conda: "selection.yml"
    threads: MAX_THREADS
    params:
        models = get_models,
        species = get_species
    shell:
        """
        bash src/homologs/ete3_evol_folder.sh \
            {input.tree_folder} \
            {input.msa_folder} \
            {output.ete3_folder} \
            {threads} \
            {params.species} \
            {params.models} \
        2> {log} 1>&2

        touch {output.tsv}

        python src/homologs/parse_ete3_evol_folder.py \
            {output.ete3_folder}/values txt \
        > {output.tsv} 2>> {log}
        """


rule selection_ete3:
    input:
        expand(
            SELECTION + "{group}/ete3.tsv",
            group=params["selection"]["foreground_branches"]
        )


rule selection_trees_filtered_group:
    input:
        tsv = SELECTION + "{group}/ete3.tsv",
        tree_folder = SELECTION + "{group}/trees"
    output:
        tree_folder = directory(SELECTION + "{group}/trees_filtered")
    log: SELECTION + "{group}/trees_filtered.log"
    benchmark: SELECTION + "{group}/trees_filtered.bmk"
    params:
        evalue = params["selection"]["ete3"]["evalue"],
        n_tests = len(params["selection"]["ete3"]["omega_zeros"].split(","))
    conda: "selection.yml"
    shell:
        """
        bash src/homologs/filter_trees_by_evalue.sh \
            {input.tsv} \
            {params.evalue} \
            {input.tree_folder} \
            {output.tree_folder} \
            {params.n_tests} \
        2> {log} 1>&2
        """


rule selection_trees_filtered:
    input:
        expand(
            SELECTION + "{group}/trees_filtered",
            group=params["selection"]["foreground_branches"]
        )


rule selection_pep_filtered_group:
    input:
        pep = HOMOLOGS + "all.pep",
        folder = SELECTION + "{group}/trees_filtered"
    output:
        folder = directory(SELECTION + "{group}/pep_filtered")
    log: SELECTION + "{group}/pep_filtered.log"
    benchmark: SELECTION + "{group}/pep_filtered.bmk"
    conda: "selection.yml"
    shell:
        """
        python src/homologs/tree_to_fasta.py \
            {input.pep} \
            {input.folder} \
            nwk \
            {output.folder} \
            fa \
        2> {log} 1>&2
        """


rule selection_pep_filtered:
    input:
        expand(
            SELECTION + "{group}/pep_filtered",
            group=params["selection"]["foreground_branches"]
        )


rule selection_cds_filtered_group:
    input:
        pep = HOMOLOGS + "all.cds",
        folder = SELECTION + "{group}/trees_filtered"
    output:
        folder = directory(SELECTION + "{group}/cds_filtered")
    log: SELECTION + "{group}/cds_filtered.log"
    benchmark: SELECTION + "{group}/cds_filtered.bmk"
    conda: "selection.yml"
    shell:
        """
        python src/homologs/tree_to_fasta.py \
            {input.pep} \
            {input.folder} \
            nwk \
            {output.folder} \
            fa \
        2> {log} 1>&2
        """


rule selection_cds_filtered:
    input:
        expand(
            SELECTION + "{group}/cds_filtered",
            group=params["selection"]["foreground_branches"]
        )


rule selection_guidance_group:
    input:
        folder = SELECTION + "{group}/cds_filtered"
    output:
        folder = directory(SELECTION + "{group}/guidance")
    log: SELECTION + "{group}/guidance.log"
    benchmark: SELECTION + "{group}/guidance.bmk"
    conda: "selection.yml"
    threads: MAX_THREADS
    params:
        msa_program = params["selection"]["guidance"]["msa_program"],
        program = params["selection"]["guidance"]["program"],
        msa_param = params["selection"]["guidance"]["msa_param"],
        bootstraps = params["selection"]["guidance"]["bootstraps"]
    shell:
        """
        PERLLIB="$CONDA_PREFIX/lib/perl5/site_perl/5.22.0"

        mkdir --parents {output.folder}

        (find {input.folder} -type f -name "*.fa" -printf "%s\t%p\n" \
        | sort --numeric --reverse --key 1,1 \
        | cut -f 2 \
        | parallel \
            --jobs {threads} \
            perl -I "$PERLLIB" src/guidance.v2.02/www/Guidance/guidance.pl \
                --seqFile {input.folder}/{{/.}}.fa \
                --msaProgram {params.msa_program} \
                --MSA_Param {params.msa_param} \
                --seqType codon \
                --outDir $PWD/{output.folder}/{{/.}} \
                --program {params.program} \
                --bootstraps {params.bootstraps} \
                --proc_num 1 \
                --genCode 1 \
        )2> {log} 1>&2

        # Extract output files
        ls -1 {output.folder} \
        | parallel \
            mv \
                {output.folder}/{{}}/*.aln.With_Names \
                {output.folder}/{{}}.fa \
        2>> {log} 1>&2
        
        # Remove dirs
        ls -1d {output.folder}/*/ | xargs rm -rf 2>> {log} 1>&2
        """


rule selection_guidance:
    input:
        expand(
            SELECTION + "{group}/guidance",
            group=params["selection"]["foreground_branches"]
        )


rule selection_trimal_group:
    input:
        msa_folder = SELECTION + "{group}/guidance"
    output:
        trimal_folder = directory(SELECTION + "{group}/trimal")
    log: SELECTION + "{group}/trimal.log"
    benchmark: SELECTION + "{group}/trimal.bmk"
    conda: "selection.yml"
    threads: MAX_THREADS
    shell:
        """
        python src/homologs/run_trimal.py \
            --input-folder {input.msa_folder} \
            --output-folder {output.trimal_folder} \
            --threads {threads} \
        2> {log} 1>&2
        """

rule selection_trimal:
    input:
        expand(
            SELECTION + "{group}/trimal",
            group=params["selection"]["foreground_branches"]
        )


rule selection_maxalign_group:
    input:
        trimal_folder = SELECTION + "{group}/trimal"
    output:
        maxalign_folder = directory(SELECTION + "{group}/maxalign")
    log: SELECTION + "{group}/maxalign.log"
    benchmark: SELECTION + "{group}/maxalign.bmk"
    conda: "selection.yml"
    threads: MAX_THREADS
    shell:
        """
        bash src/homologs/maxalign_folder.sh \
            {input} fa \
            {output} fa \
            {threads} \
        2> {log} 1>&2
        """


rule selection_maxalign:
    input:
        expand(
            SELECTION + "{group}/maxalign",
            group=params["selection"]["foreground_branches"]
        )


rule selection_fastcodeml_group:
    input:
        tree = TREE + "exabayes/ExaBayes.rooted.nwk",
        maxalign_folder = SELECTION + "{group}/maxalign"
    output:
        results_folder = directory(SELECTION + "{group}/fastcodeml"),
        results_tsv = SELECTION + "{group}/fastcodeml.tsv"
    log: SELECTION + "{group}/fastcodeml.log"
    benchmark: SELECTION + "{group}/fastcodeml.bmk"
    conda: "selection.yml"
    threads: MAX_THREADS
    params:
        omega_zeros = params["selection"]["fastcodeml"]["omega_zeros"],
        target_species = get_species,
        min_foreground = get_min_foreground,
        min_background = get_min_background,
        binary = params["selection"]["fastcodeml"]["binary"]
    shell:
        """
        bash src/homologs/run_fastcodeml_folder.sh \
            --tree {input.tree} \
            --input-msa-folder {input.maxalign_folder} \
            --omega-zeros {params.omega_zeros} \
            --target-species {params.target_species} \
            --min-foreground {params.min_foreground} \
            --min-background {params.min_background} \
            --output-folder {output.results_folder} \
            --output-pvalues {output.results_tsv} \
            --jobs {threads} \
            --fastcodeml-binary {params.binary} \
        2> {log} 1>&2
        """

rule selection_fastcodeml:
    input:
        expand(
            SELECTION + "{group}/fastcodeml.tsv",
            group=params["selection"]["foreground_branches"]
        )


# rule selection_pcorrection_group:
#     input:
#         tsv_ete = SELECTION + "{group}/ete3.tsv",
#         tsv_fastcodeml = SELECTION + "{group}/fastcodeml.tsv"
#     output:
#         tsv_corrected = SELECTION + "{group}/pcorrection.tsv"
#     log: SELECTION + "{group}/pcorrection.log"
#     benchmark: SELECTION + "{group}/pcorrection.bmk"
#     conda: "selection.yml"
#     params:
#         pvalue = params["selection"]["correction"]["pvalue"]
#     shell:
#         """
#         python src/homologs/correct_pvalues.py \
#             --ete3 {input.tsv_ete} \
#             --fastcodeml {input.tsv_fastcodeml} \
#             --output {output.tsv_corrected} \
#             --pvalue {params.pvalue} \
#         2> {log} 1>&2 
#         """


# rule selection_pcorrection:
#     input:
#         expand(
#             SELECTION + "{group}/pcorrection.tsv",
#             group=params["selection"]["foreground_branches"]
#         )


# rule selection_selected_msas_group:
#     input:
#         tsv_corrected = SELECTION + "{group}/pcorrection.tsv",
#         msa_folder = SELECTION + "{group}/maxalign"
#     output:
#         msa_folder = directory(SELECTION + "{group}/selected_msas/")
#     log: SELECTION + "{group}/selected_msas.log"
#     benchmark: SELECTION + "{group}/selected_msas.bmk"
#     conda: "selection.yml"
#     shell:
#         """
#         awk '$6 == "True"' < {input.tsv_corrected} \
#         | cut -f 1 \
#         | parallel --jobs 1 --keep-order \
#             cp {input.msa_folder}/{{}}.fa {output.msa_folder} \
#         2> {log} 1>&2
#         """


# rule selection_selected_msas:
#     input:
#         expand(
#             SELECTION + "{group}/selected_msas/",
#             group=params["selection"]["foreground_branches"]
#         )


rule selection_speed_group:
    """Compute the evolution speeds of the orthogroups.

    Compute the dN and dS of the one-ratio (M0) and free-ratio (b_free)
    models to look later on for synonymous-site saturation and advantageous
    allele rising.
    """
    input:
        msa_folder = SELECTION + "{group}/maxalign",
        tree = TREE + "exabayes/ExaBayes.rooted.nwk"
    output:
        speed_folder = directory(SELECTION + "{group}/speed/"),
        speed_tsv = SELECTION + "{group}/speed.tsv"
    log: SELECTION + "{group}/speed.log"
    benchmark: SELECTION + "{group}/speed.bmk"
    conda: "selection.yml"
    threads: MAX_THREADS
    params:
        target_species = get_species,
    shell:
        """
        bash src/homologs/evolution_speed.sh \
            --input-tree {input.tree} \
            --input-msa-folder {input.msa_folder} \
            --target-species {params.target_species} \
            --jobs {MAX_THREADS} \
            --output-folder {output.speed_folder} \
            --output-file {output.speed_tsv} \
        2> {log} 1>&2
        """




rule selection_speed:
    input:
        expand(
            SELECTION + "{group}/speed/",
            group=params["selection"]["foreground_branches"]
        )
