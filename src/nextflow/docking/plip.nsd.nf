#!/usr/bin/env nextflow

params.ligands = 'ligands.data.gz'
params.protein = 'protein.pdb.gz'
params.chunk = 25
params.score = null
params.limit = 0
params.digits = 4

ligands = file(params.ligands)
protein = file(params.protein)

process splitter {

    container 'informaticsmatters/pli:latest'
    beforeScript 'chmod g+w .'

    input:
    file ligands

    output:
    file 'ligand_part*.sdf.gz' into ligand_parts mode flatten
    file 'ligand_part_metrics.txt' into splitter_metrics

    """
    python -m pipelines_utils_rdkit.filter -i $ligands -c $params.chunk -l $params.limit -d $params.digits -o ligand_part -of sdf --meta
    """
}


/* Scores each file from the ligand_parts channel sending each resulting SD file to the results channel
*/
process pli_scoring {

    container 'informaticsmatters/pli:latest'
    beforeScript 'chmod g+w .'

	input:
    file part from ligand_parts
	file protein

    output:
    file 'scored_part*.sdf' into scored_parts

    """
	python -m pipelines.docking.plip -i $part -pdb $protein -o ${part.name.replace('ligand', 'scored')[0..-8]} -of sdf --no-gzip ${params.score ? ' -t ' + params.score : ''} --threads 1 &> scored_out.log
    """
}

process joiner {

    container 'informaticsmatters/pli:latest'
    beforeScript 'chmod g+w .'
    publishDir baseDir, mode: 'link'

    input:
    file parts from scored_parts.collect()
    file 'splitter_metrics.txt' from splitter_metrics

    output:
    file 'output.data.gz'
    file 'output_metrics.txt'
    file 'output.metadata'

    """
    cat scored_part*.sdf | python -m pipelines_utils_rdkit.filter -if sdf -of json -o output --meta --thin
    mv output_metrics.txt joiner_metrics.txt
    grep '__InputCount__' splitter_metrics.txt | sed s/__InputCount__/PLI/ > output_metrics.txt
    grep '__InputCount__' splitter_metrics.txt >> output_metrics.txt
    grep '__OutputCount__' joiner_metrics.txt >> output_metrics.txt
    echo '{"type":"org.squonk.types.BasicObject","valueClassMappings":{"pliff_cscore":"java.lang.Float","pliff_iscore":"java.lang.Float","pliff_tscore":"java.lang.Float","pliff_gscore":"java.lang.Float","pliff_score":"java.lang.Float","pliff_nb_score":"java.lang.Float"}}' > output.metadata
    """
}
