#!/usr/local/bin/perl

###############################################################################
# generate buildDetail tables 
###############################################################################
use strict;
use IO::Handle;
use lib "$ENV{SBEAMS}/lib/perl";

#use CGI::Carp qw(fatalsToBrowser croak);
use vars qw($PROGRAM_FILE_NAME);

use SBEAMS::Connection qw($q $log);
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Tables;
use SBEAMS::Connection::DataTable;

use SBEAMS::PeptideAtlas;
use SBEAMS::PeptideAtlas::Settings;
use SBEAMS::PeptideAtlas::Tables;
use SBEAMS::PeptideAtlas::Utilities;

my $sbeams = new SBEAMS::Connection;
$sbeams->setSBEAMS_SUBDIR($SBEAMS_SUBDIR);
my $atlas = new SBEAMS::PeptideAtlas;
$atlas->setSBEAMS($sbeams);

use Getopt::Long;

my %OPTIONS;

#### Process options
GetOptions(\%OPTIONS,"build_id:i", "respect");
my $build_id = $OPTIONS{build_id} || die "need build_id\n";
my $build_path = get_build_path( build_id => $build_id );
my ($organism, $organism_id) = getBuildOrganism( build_id => $build_id );

$sbeams->update_PA_table_variables($build_id);

my $fh;
open ($fh, ">$build_path/analysis/build_detail_tables.tsv.tmp") or die "cannot open $build_path/analysis/build_detail_tables.tsv\n";
$fh->autoflush;

##Build Overview
print "getting build_overview table\n";

my %mass_modifications = ();
my $n_identified_spectra=0;
get_build_overview (fh=>$fh, 
                    build_id=>$build_id, 
                    build_path=>$build_path,
                    mass_modifications=>\%mass_modifications,
                    n_identified_spectra => \$n_identified_spectra );

print "getting what_is_new table\n";
my ($what_is_new, $new_sample_ids) = $atlas->get_what_is_new($build_id, 1);
if ($what_is_new){
	foreach my $row (@$what_is_new){
		print $fh "what_is_new|". join("\t", @$row) ."\n";
	}
	print $fh "what_is_new|sample_ids\t", join(",", @$new_sample_ids) ."\n";
}
undef $what_is_new;

print "getting proteome coverage\n";
my $proteomeComponentOrder_file = "$PHYSICAL_BASE_DIR/lib/conf/PeptideAtlas/ProteomeComponentOrder.txt";
my @patterns =();
if (open (O, "<$proteomeComponentOrder_file")){
	 while (my $line = <O>){
		 chomp $line;
		 next if ($line =~ /^#/ ||  $line =~ /^$/);
		 my ($org_id, $str) = split(/\t/, $line);
		 if ($org_id == $organism_id){
				push @patterns,$line;
		 }
	 }
}
my $proteome_coverage;
my $ptm_coverage;
if (@patterns){
  $proteome_coverage = $atlas->get_proteome_coverage_new ($build_id,\@patterns, 1);
  $ptm_coverage = $atlas->get_ptm_coverage ($build_id,\@patterns, 1);
}else{
  $proteome_coverage  = $atlas->get_proteome_coverage ($build_id, 1);
}

#shift @$proteome_coverage;
#print $fh "proteome_coverage|Database\tN_Seqs\tN_Obs_Prots\tPct_Obs\n";
foreach my $row (@{$proteome_coverage->{table}}){
  #next if($row->[1] == 0);
  print $fh "proteome_coverage||".  join("\t", @$row). "\n";;
}

undef $proteome_coverage;

if ($ptm_coverage){
	foreach my $ptm_type (sort {$a cmp $b} keys %{$ptm_coverage}){
    foreach my $row (@{$ptm_coverage->{$ptm_type}}){
		  print $fh "ptm_coverage_$ptm_type|".  join("\t", @$row) ."\n";
  	}
  }
	undef $ptm_coverage;
}

print "getting Experiment Contribution table\n";
my $exp_contrib_table = get_sample_info( $build_id );
foreach my $row (@$exp_contrib_table){
  if ($organism !~ /(human|Arabidopsis|Maize|Bburgdorferi|mouse|Canine|coli|candida)/i){
		 pop @$row;
		 pop @$row;
  } 
  print $fh "exp_contrib_table|".  join("\t", @$row) ."\n";
}

undef $exp_contrib_table;

print "getting Dataset Contribution table\n";
my $dataset_contrib_table = get_dataset_contrib_info($build_id);

foreach my $row (@$dataset_contrib_table){
  print $fh "dataset_contrib_table|".  join("\t", @$row) ."\n";
}

print "getting Dataset Protein Info\n";
my $dataset_protein_info = get_dataset_protein_info_old( build_id => $build_id);

foreach my $row (@$dataset_protein_info){
  print $fh "dataset_protein_info|".  join("\t", @$row) ."\n";
}
print "getting Dataset Specific Protein Identification\n";
my $dataset_spec_protein_info =  get_dataset_spec_protein_info( build_id => $build_id);
foreach my $row (@$dataset_spec_protein_info){
  print $fh "dataset_spec_protein_info|".  join("\t", @$row) ."\n";
}

print $fh "mass_modifications|Modification\tN Obs\tPercent Identified Spectra\n";

foreach my $mod (sort {$mass_modifications{mod}{$b} <=> $mass_modifications{mod}{$a}} keys %{$mass_modifications{mod}}){
  print $fh "mass_modifications|$mod\t". add_thousand_separator($mass_modifications{mod}{$mod}); 
  print $fh sprintf("\t%.2f\n", $mass_modifications{mod}{$mod}*100/$n_identified_spectra);
}

if ($organism =~ /Bburgdorferi/i){
  print "getting chromosome coverage data\n";
  my $limit = 3;
  my $sql = qq~
		SELECT NeXtProt_Mapping_id, chromosome, PeptideAtlas_Category 
		FROM $TBAT_NEXTPROT_CHROMOSOME_MAPPING NCM
    JOIN $TBAT_NEXTPROT_MAPPING NM ON (NM.id = NCM.NeXtProt_Mapping_id)
    WHERE NM.atlas_build_id = $build_id 
    ORDER BY NCM.NeXtProt_Mapping_id, NCM.chromosome
	 ~;
#			SELECT top $limit NM.id
#			FROM $TBAT_NEXTPROT_MAPPING NM 
#			WHERE NM.atlas_build_id = $build_id
#			ORDER BY pa_mapping_date DESC
#    )  

  my @result = $sbeams->selectSeveralColumns($sql);
  my %data = ();
  $sql = qq~
	 SELECT id,comment 
	 FROM $TBAT_NEXTPROT_MAPPING
	 WHERE atlas_build_id = $build_id
  ~;
  my %ncmid2borreliaIso=$sbeams->selectTwoColumnHash($sql);
  foreach my $row (@result){
     my ($id, $chr,$PAcat) = @$row;
     die "ERROR: chromosome mapping id $id not found for Borrelia\n" if (! $ncmid2borreliaIso{$id});
     $chr = 'na' if (! $chr);
     $chr =~ s/plsm\_//;
     #if ($ncmid2borreliaIso{$id} eq 'B31-5A4' || $ncmid2borreliaIso{$id} eq 'JD1'){
        if ($chr =~ /plasmid/){
					if ($chr =~ /plasmid\s+p(26|32|9)/){
						$chr =~ s/plasmid\s+p/cp/;
					}else{
            $chr =~ s/plasmid\s+p/lp/;
          }
        }
     $chr =~ s/plasmid.//; 
     #}
     if ($PAcat !~ /not observed/i){
       $data{$ncmid2borreliaIso{$id}}{$chr}{'Observed'}++;
     }
     $data{$ncmid2borreliaIso{$id}}{$chr}{'All'}++;
  }
  foreach my $org (values %ncmid2borreliaIso){
    foreach my $chr (sort {$a cmp $b} keys %{$data{$org}}){
      print $fh "chr_plot|$org\t$chr\t$data{$org}{$chr}{'All'}\t$data{$org}{$chr}{'Observed'}\n";
    }
  }
}

print $fh "\n";

if ($organism =~ /(human|Arabidopsis|Maize|Bburgdorferi|mouse|Canine|coli|candida)/i){ 

  print "getting plot Peptide Identification by Sample Category data\n";

	my $sql = qq~
				SELECT SC.name as NAME,
							 SC.ID, 
				       COUNT (DISTINCT PI.PEPTIDE_ID) AS CNT
				FROM $TBAT_PEPTIDE_INSTANCE PI
				JOIN $TBAT_PEPTIDE_INSTANCE_SAMPLE PIS ON ( PIS.PEPTIDE_INSTANCE_ID = PI.PEPTIDE_INSTANCE_ID )
				JOIN $TBAT_SAMPLE S  ON (PIS.SAMPLE_ID = S.SAMPLE_ID)
				JOIN $TBAT_SAMPLE_CATEGORY SC ON (S.SAMPLE_CATEGORY_ID = SC.ID) 
				WHERE 1=1
				AND PI.ATLAS_BUILD_ID = $build_id 
				GROUP BY SC.NAME,SC.ID
        ORDER BY SC.NAME DESC
			 ~;
      
	my @result = $sbeams->selectSeveralColumns($sql);
  if (@result > 1){
		foreach my $row (@result){
			print $fh "cat_plot|". join("\t", @$row) ."\n";
		}
  }

}
close $fh;
exit;

####################################################

sub getBuildOrganism {
  my %args = @_;
  my $sql = qq~
             SELECT O.organism_name, O.organism_id 
             FROM $TBAT_ATLAS_BUILD AB 
             JOIN $TBAT_BIOSEQUENCE_SET BS ON (AB.biosequence_set_id = BS.biosequence_set_id)  
             JOIN $TB_ORGANISM O on (BS.organism_id = O.organism_id)
             WHERE AB.atlas_build_id = $args{build_id}

   ~;;
  my @row = $sbeams->selectSeveralColumns($sql); 
  if (! @row){
    die "cannot find organism id for build=$build_id\n";
  }
  return @{$row[0]};
}

sub get_dataset_spec_protein_info {
  my %args = @_;
  my $build_id = $args{build_id};

  my $sql = qq~
   SELECT A.repository_id , A.NAME, count (distinct A.ID) as cnt
   FROM (
     SELECT PID.dataset_specific_id as repository_id,
            PRL.LEVEL_NAME AS NAME,
            PID.biosequence_id as ID
     FROM $TBAT_PROTEIN_IDENTIFICATION PID 
     JOIN  $TBAT_PROTEIN_PRESENCE_LEVEL PRL
     ON (PID.PRESENCE_LEVEL_ID = PRL.PROTEIN_PRESENCE_LEVEL_ID)
     WHERE 1 = 1
           AND atlas_build_id IN ($build_id)
           AND dataset_specific_id IS NOT NULL
           AND dataset_specific_id != ''
           AND dataset_specific_id != 'OTHERS'
     UNION
     SELECT BR.DATASET_SPECIFIC_ID AS  repository_id, 
            BRT.RELATIONSHIP_NAME AS NAME, 
            BR.RELATED_BIOSEQUENCE_ID as ID 
     FROM $TBAT_BIOSEQUENCE_RELATIONSHIP BR
     JOIN $TBAT_BIOSEQUENCE_RELATIONSHIP_TYPE BRT
     ON (BR.RELATIONSHIP_TYPE_ID = BRT.BIOSEQUENCE_RELATIONSHIP_TYPE_ID)
     WHERE 1 = 1
           AND atlas_build_id IN ($build_id)
           AND dataset_specific_id IS NOT NULL
           AND dataset_specific_id != '' 
           AND dataset_specific_id != 'OTHERS'
   ) AS A
   GROUP BY A.repository_id, A.NAME
   order by cnt DESC  
  ~;

  my @rows = $sbeams->selectSeveralColumns($sql);
  return [] if (@rows < 1);
  my %unique_prot2dataset_cnt;
  my $possibly_distinguished = 0; 
  foreach my $row(@rows){
    my ($repository_id, $name,$cnt) =@$row;
    $unique_prot2dataset_cnt{$repository_id}{$name} = $cnt;
    if ($name =~ /(possibly_distinguished|ntt-subsumed)/i){
      $possibly_distinguished++;
    }
  } 
  ## older builds
  return [] if ($possibly_distinguished > 0);

  my @level_names = ('canonical','noncore-canonical','indistinguishable representative'  ,'representative'
                     ,'marginally distinguished','weak','insufficient evidence','indistinguishable','subsumed');
  $sql =qq~;
    SELECT LEVEL_NAME AS NAME, PROTEIN_PRESENCE_LEVEL_ID AS ID
    FROM $TBAT_PROTEIN_PRESENCE_LEVEL
    UNION 
    SELECT RELATIONSHIP_NAME AS NAME, BIOSEQUENCE_RELATIONSHIP_TYPE_ID AS ID
    FROM $TBAT_BIOSEQUENCE_RELATIONSHIP_TYPE 
  ~;
  my %protein_level_ids = $sbeams->selectTwoColumnHash($sql);

  my @headings =('Dataset', @level_names);
  my @sortable=();
  my @align=();
  for my $col ( @headings ) {
    $col =~ s/(\w+)/\u$1/g;
    push @sortable, $col,$col;
    push @align, 'center';
  }
  $align[0] = 'left';
  my @records = ();
  foreach my $repository_id (sort {$a cmp $b } keys %unique_prot2dataset_cnt){ 
    my @row =();
    push @row , $repository_id;
    foreach my $level_name (@level_names){
      my $cnt = $unique_prot2dataset_cnt{$repository_id}{$level_name} || '';
      if (defined $unique_prot2dataset_cnt{$repository_id}{$level_name}){
         my $cnt = $unique_prot2dataset_cnt{$repository_id}{$level_name};
         push @row , $cnt;
      }else{
         push @row ,'';
      }
    }
    push @records, \@row;
  }
  unshift @records, \@headings;
  return \@records;

}

# less informative sample contribution plot
sub get_build_plots {
  my %args = @_;
  my $build_id = $args{build_id};
  my $chart_div = $args{chart_div};
  my $sample_arrayref = $args{sample_arrayref};
  my $column_name_ref = $args{column_name_ref};
  my $table = "<table>\n";

  my ( $tr, $link ) = $sbeams->make_table_toggle( name    => 'build_plot',
                                                  visible => 1,
                                                  tooltip => 'Show/Hide Section',
                                                  imglink => 1,
                                                  sticky  => 1 );

  $table .= $atlas->encodeSectionHeader(
      text => 'Experiment Contribution Plots',
      span => 4,
      trinfo => "class=hoverable",
      LMTABS => 1,
      divname => 'experiment_contribution_div',
      no_toggle => 0,
      link => $link,
  );

  my $chart = $atlas->displayExperiment_contri_plotly(
      tr => $tr,
      data_ref=>$sample_arrayref,
      column_name_ref => $column_name_ref, 
  );

  $table .= qq~
   $chart
    </table>
  ~;
 
  return $table;
}

# General build info, date, name, organism, specialty, default
sub get_build_overview {
  my %args = @_;
  my $fh = $args{fh};
  my $build_id = $args{build_id};
  my $build_path = $args{build_path};
  my $mass_modifications = $args{mass_modifications};
  my $n_identified_spectra = $args{n_identified_spectra};

  print "build_id=$build_id\nbuild_path=$build_path\n";

 
  my $build_info = $sbeams->selectrow_hashref( <<"  BUILD" );
  SELECT atlas_build_name, probability_threshold, atlas_build_description, 
  build_date, set_name, protpro_PSM_FDR_per_expt
  FROM $TBAT_ATLAS_BUILD AB 
  JOIN $TBAT_BIOSEQUENCE_SET BS ON AB.biosequence_set_id = BS.biosequence_set_id
  WHERE atlas_build_id = $build_id 
  AND AB.record_status <> 'D'
  BUILD


  ## check if mayu output available
  if ( -e "$build_path/analysis/Mayu_out.csv" ) {
     my $line = `tail -1 "$build_path/analysis/Mayu_out.csv"`;
     if ($line){
			 my @elms = split(",", $line);
			 $build_info->{'Build PSM FDR'} = sprintf("%.5f" , $elms[2]);
			 $build_info->{'Build peptide FDR'} = sprintf("%.4f", $elms[12]);
       $build_info->{'Build protein FDR'}  = sprintf("%.4f", $elms[18]);
     }
  }
#  for my $k ( keys( %$build_info ) ) { print STDERR "$k => $build_info->{$k}\n"; }
  my $build_name = $build_info->{atlas_build_name};
  my $phospho_info;
  
  my %processed_id = ();

	my $sql = qq~
		 SELECT mp.modified_peptide_instance_id,  mp.modified_peptide_sequence, mp.n_observations
		 FROM $TBAT_PEPTIDE_INSTANCE PI
		 JOIN $TBAT_MODIFIED_PEPTIDE_INSTANCE MP ON (PI.PEPTIDE_INSTANCE_ID = MP.PEPTIDE_INSTANCE_ID)
		 JOIN $TBAT_PEPTIDE_MAPPING PM ON (PI.PEPTIDE_INSTANCE_ID = PM.PEPTIDE_INSTANCE_ID)
		 JOIN $TBAT_BIOSEQUENCE B ON (B.BIOSEQUENCE_ID = PM.MATCHED_BIOSEQUENCE_ID)
		 AND PI.ATLAS_BUILD_ID = $build_id
		 AND B.BIOSEQUENCE_NAME NOT LIKE 'CONTAM%' 
		 AND B.BIOSEQUENCE_NAME NOT LIKE 'DECOY%'
	 ~;

	my @rows = $sbeams->selectSeveralColumns($sql);
  
  foreach my $row(@rows){
     my ($id, $mod_pep, $n_obs) = @$row;
     next if ($processed_id{$id});  
     $processed_id{$id} =1;
     $mass_modifications->{seq}{$mod_pep} =1;
     my %mods = ();


		 if ($mod_pep =~ /^(\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\])\-(.*)/){
	 		 $mod_pep = "n$1$2";
		 }
		 if ($mod_pep =~ /(.*)\-(\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\])$/){
	  	 $mod_pep = "$1c$2";
		 }

     
     while ($mod_pep =~ /([ncA-Z](?:\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\])?)/g){
        my $part = $1;
        if ($part =~ /\[(.*)\]/){
           $mods{$part}=$n_obs;
        }
     }  
     foreach my $mod (keys %mods){
       $mass_modifications->{mod}{$mod} +=$mods{$mod};
     }
  } 

  if ($build_name =~ /phospho/i){
		 my %result =();
		 foreach my $mod_pep (keys %{$mass_modifications->{seq}}){ 
			 $mod_pep =~ s/([^ASTY])\[\d+\]/$1/g;
			 $mod_pep =~ s/[nc]//g;
       my @m = $mod_pep =~ /[ASTY]\[/g;
       if (@m == 1){
			   $result{'singly_phosphorylated'}{$mod_pep} =1;
       }elsif(@m == 2){
          $result{'doubly_phosphorylated'}{$mod_pep} =1;
       }else{
          $result{'over_2_phosphorylated'}{$mod_pep} =1;
       }
		 }
		 foreach my $type(keys %result){
			 $phospho_info->{$type} = scalar keys %{$result{$type}};
		 }
  }

  my $pep_count = $sbeams->selectrow_hashref( <<"  PEP" );
  SELECT COUNT(*) cnt,  SUM(n_observations) obs
	FROM (
		SELECT DISTINCT PI.PEPTIDE_INSTANCE_ID, PI.N_OBSERVATIONS
		FROM $TBAT_PEPTIDE_INSTANCE PI
		JOIN $TBAT_PEPTIDE_MAPPING PM ON (PI.PEPTIDE_INSTANCE_ID = PM.PEPTIDE_INSTANCE_ID)
		JOIN $TBAT_BIOSEQUENCE B ON (PM.MATCHED_BIOSEQUENCE_ID = B.BIOSEQUENCE_ID)
		WHERE  ATLAS_BUILD_ID= $build_id AND B.BIOSEQUENCE_NAME NOT LIKE 'DECOY%'
          AND B.BIOSEQUENCE_NAME NOT LIKE 'CONTAM%' 
	) A
  PEP

  my $mod_pep_count = $sbeams->selectrow_hashref( <<"  PEP" );
    SELECT FORMAT (count(DISTINCT MPI.MODIFIED_PEPTIDE_INSTANCE_ID), '#,#') cnt
    FROM $TBAT_PEPTIDE_INSTANCE PI 
    JOIN $TBAT_MODIFIED_PEPTIDE_INSTANCE MPI ON (MPI.PEPTIDE_INSTANCE_ID = PI.PEPTIDE_INSTANCE_ID)
    JOIN $TBAT_PEPTIDE_MAPPING PM ON (MPI.PEPTIDE_INSTANCE_ID = PM.PEPTIDE_INSTANCE_ID)
    JOIN $TBAT_BIOSEQUENCE B ON (PM.MATCHED_BIOSEQUENCE_ID = B.BIOSEQUENCE_ID)
    WHERE  PI.ATLAS_BUILD_ID= $build_id AND B.BIOSEQUENCE_NAME NOT LIKE 'DECOY%'
          AND B.BIOSEQUENCE_NAME NOT LIKE 'CONTAM%' 
  PEP

  $$n_identified_spectra = $pep_count->{obs};

  my ($pep_count_respect,$mod_pep_count_respect);
  if ($OPTIONS{respect}){
#		my $pep_count_respect = $sbeams->selectrow_hashref( <<"		PEP" );
#		SELECT COUNT(DISTINCT PI.PEPTIDE_INSTANCE_ID) cnt
#		FROM (
#      SELECT A.PEPTIDE_INSTANCE_ID, STRING_AGG(CONVERT(NVARCHAR(max),ISNULL(S.chimera_level,'1')), ',') as level 
#			FROM $TBAT_PEPTIDE_INSTANCE PI
#			JOIN $TBAT_PEPTIDE_MAPPING PM ON (PM.peptide_instance_id = PI.peptide_instance_id)
#			JOIN $TBAT_MODIFIED_PEPTIDE_INSTANCE MPI ON ( PI.peptide_instance_id = MPI.peptide_instance_id )
#			JOIN $TBAT_SPECTRUM_IDENTIFICATION SI ON ( MPI.modified_peptide_instance_id = SI.modified_peptide_instance_id )
#			JOIN $TBAT_SPECTRUM S ON ( SI.spectrum_id = S.spectrum_id )
#			JOIN $TBAT_BIOSEQUENCE B ON  (B.BIOSEQUENCE_ID = PM.MATCHED_BIOSEQUENCE_ID)
#			WHERE 1=1
#      AND ATLAS_BUILD_ID= $build_id 
#      AND B.BIOSEQUENCE_NAME NOT LIKE 'DECOY%'
#      AND B.BIOSEQUENCE_NAME NOT LIKE 'CONTAM%'
#      GROUP BY PI.PEPTIDE_INSTANCE_ID
#		)A
#    WHERE A.level not like '%1%'
#		PEP
    $pep_count_respect = $sbeams->selectrow_hashref( <<"   PEP" );
    SELECT COUNT(DISTINCT A.PEPTIDE_INSTANCE_ID) cnt
    FROM (
      SELECT DISTINCT PI.PEPTIDE_INSTANCE_ID
      FROM $TBAT_PEPTIDE_INSTANCE PI
      JOIN $TBAT_MODIFIED_PEPTIDE_INSTANCE MPI ON ( PI.peptide_instance_id = MPI.peptide_instance_id )
      JOIN $TBAT_SPECTRUM_IDENTIFICATION SI ON ( MPI.modified_peptide_instance_id = SI.modified_peptide_instance_id )
      JOIN $TBAT_SPECTRUM S ON ( SI.spectrum_id = S.spectrum_id )
      WHERE 1=1
      AND PI.ATLAS_BUILD_ID= $build_id
      AND S.chimera_level > 1
      AND PI.PEPTIDE_INSTANCE_ID not in
      ( SELECT distinct PI2.PEPTIDE_INSTANCE_ID
				FROM $TBAT_PEPTIDE_INSTANCE PI2
				JOIN $TBAT_MODIFIED_PEPTIDE_INSTANCE MPI2 ON ( PI2.peptide_instance_id = MPI2.peptide_instance_id )
				JOIN $TBAT_SPECTRUM_IDENTIFICATION SI2 ON ( MPI2.modified_peptide_instance_id = SI2.modified_peptide_instance_id )
				JOIN $TBAT_SPECTRUM S2 ON ( SI2.spectrum_id = S2.spectrum_id )
				WHERE 1=1
				AND PI2.ATLAS_BUILD_ID= $build_id
				AND (S2.chimera_level is null or S2.chimera_level = 1)
      )
    )A
   PEP
  }  
  my $smpl_count = $sbeams->selectrow_hashref( <<"  SMPL" );
  SELECT COUNT(*) cnt 
  FROM $TBAT_ATLAS_SEARCH_BATCH ASB 
  JOIN $TBAT_ATLAS_BUILD_SEARCH_BATCH ABSB ON (ASB.atlas_search_batch_id = ABSB.atlas_search_batch_id )
  WHERE atlas_build_id = $build_id
  AND ASB.record_status = 'N'
  SMPL

  my $dataset_count = $sbeams->selectrow_hashref( <<"  DATASET" );
  SELECT  COUNT(*) cnt,
          FORMAT (SUM(cast (n_searched_spectra as bigint)), '#,#') n_searched_spectra,
          FORMAT (SUM(n_runs),  '#,#') n_runs
          --SUM(cast (n_good_spectra as bigint)) n_good_spectra
  FROM $TBAT_DATASET_STATISTICS
  WHERE ATLAS_BUILD_ID = $build_id
  DATASET

  my %prot_count =();
  my %core_prot = ();
  my %protein_presence_level = $sbeams->selectTwoColumnHash( <<"  PROT" );
  SELECT BS.biosequence_name , PPL.level_name
  FROM $TBAT_PROTEIN_IDENTIFICATION PID
  JOIN $TBAT_PROTEIN_PRESENCE_LEVEL PPL
  ON PPL.protein_presence_level_id = PID.presence_level_id
  JOIN $TBAT_BIOSEQUENCE BS
  ON BS.biosequence_id = PID.biosequence_id
  WHERE PID.atlas_build_id = $build_id
  AND PPL.level_name in 
      ('canonical', 'noncore-canonical', 'indistinguishable representative', 
       'marginally distinguished', 'representative',
       'possibly_distinguished','weak', 'insufficient evidence')
  AND BS.biosequence_name NOT LIKE 'DECOY%'
  AND BS.biosequence_name NOT LIKE '%UNMAPPED%'
  AND BS.biosequence_name NOT LIKE '%CONTAM%'
  AND BS.biosequence_desc NOT LIKE '%common contaminant%'
  PROT

  if ( -e "$build_path/DATA_FILES/Core20k.txt" ) {
     foreach my $line (`cat $build_path/DATA_FILES/Core20k.txt`){
        chomp $line;
        $core_prot{$line} =1;
     } 
  }else{
     die "$build_path/DATA_FILES/Core20k.txt file missing\n";
  }
  foreach my $protein (keys %protein_presence_level){
    if (defined $core_prot{$protein}){
       $prot_count{core}{$protein_presence_level{$protein}}++;
    }else{
       $prot_count{noncore}{$protein_presence_level{$protein}}++;
    }
  }

  $build_info->{build_date} =~ s/^([0-9-]+).*$/$1/;
 
  print $fh "build_overview|atlas_build_name\t$build_info->{atlas_build_name}\n";
  print $fh "build_overview|atlas_build_description\t$build_info->{atlas_build_description}\n";
  print $fh "build_overview|set_name\t$build_info->{set_name}\n";
  print $fh "build_overview|build_date\t$build_info->{build_date}\n";
  print $fh "build_overview|smpl_count\t$smpl_count->{cnt}\n";
  print $fh "build_overview|dataset_count\t$dataset_count->{cnt}\n";
  print $fh "build_overview|n_runs\t$dataset_count->{n_runs}\n";
  print $fh "build_overview|protpro_PSM_FDR_per_expt\t$build_info->{protpro_PSM_FDR_per_expt}\n"
             if ($build_info->{protpro_PSM_FDR_per_expt});
  print $fh "build_overview|Build PSM FDR\t$build_info->{'Build PSM FDR'}\n"
             if ($build_info->{'Build PSM FDR'});
  print $fh "build_overview|Build peptide FDR\t$build_info->{'Build peptide FDR'}\n"
             if ($build_info->{'Build peptide FDR'});
  print $fh "build_overview|Build protein FDR\t$build_info->{'Build protein FDR'}\n"
             if ($build_info->{'Build protein FDR'});

  print $fh "build_overview|probability_threshold\t$build_info->{probability_threshold}\n";
  print $fh "build_overview|n_searched_spectra\t$dataset_count->{n_searched_spectra}\n";
  #print $fh "build_overview|n_good_spectra\t$dataset_count->{n_good_spectra}\n";
  print $fh "build_overview|pep_count_obs\t$pep_count->{obs}\n";
  print $fh "build_overview|pep_count_cnt\t$pep_count->{cnt}\n";
  print $fh "build_overview|pep_count_respect\t$pep_count_respect->{cnt}\n" if ($pep_count_respect);
  print $fh "build_overview|modpep_count\t$mod_pep_count->{cnt}\n";


  foreach my $t (qw(core noncore)){
    my $s = 'CoreProteome Protein Presence Levels';
    if ($t eq 'noncore'){
      $s = 'Noncore-Proteome Protein Presence Levels';
    }
		foreach my $key (sort {$a cmp $b} keys %{$prot_count{$t}}){
			 if ($key =~ /canonical/i){
				 print $fh "build_overview|$s|$key\t$prot_count{$t}{$key}\n";
			 }
		}
		foreach my $key (sort {$a cmp $b} keys %{$prot_count{$t}}){
			 if ($key !~ /canonical/i){
				 print $fh "build_overview|$s|$key\t$prot_count{$t}{$key}\n";
			 }
		}
  }
  foreach my $key (sort {$a cmp $b} keys %$phospho_info){
    print $fh "build_overview|PhosphoProteome Summary|$key\t$phospho_info->{$key}\n";
  }
}

# Peptide build stats
sub get_sample_info {
  my $build_id = shift;

  # Get a list of accessible project_ids
  #### Define some variables needed to build the query
  my @column_array = (
      ["repository_identifiers","S.repository_identifiers","Dataset"],
      ["sample_id", "S.sample_id","Experiment ID"],
      ["sample_tag", "sample_tag", "Experiment Tag"],
      ["n_runs","SBS.n_runs", "MS Runs"],
      ["n_searched_spectra", "SBS.n_searched_spectra", "Spectra Searched"],
      ["n_good_spectra", "n_good_spectra", "Spectra ID'd"],
      ["per_id", "CASE WHEN SBS.n_searched_spectra > 0 THEN FORMAT((n_good_spectra*1.00)/(SBS.n_searched_spectra/1.00), 'P2') ELSE '' END", "%Spectra ID'd"],
      ["n_distinct_peptides", "n_distinct_peptides","Distinct Peptides"],
      ["n_uniq_contributed_peptides", "n_uniq_contributed_peptides", "Unique Peptides"],
      ["n_progressive_peptides", "n_progressive_peptides", "Added Peptides"],
      ["cumulative_n_peptides", "cumulative_n_peptides", "Cumulative Peptides"],
      ["n_canonical_proteins", "n_canonical_proteins", "Distinct Canonical Proteins"],
      ["n_unique_canonical_prots", "''", "Unique Canonical Proteins"],
      ["n_unique_prots", "''", "Unique All Proteins"],
      ["n_added_canonical_prots", "''", "Added Canonical Proteins"],
      ["cumulative_n_proteins", "cumulative_n_proteins", "Cumulative Canonical Proteins"],
      ["date_created", "CONVERT(VARCHAR(10), PE.date_created, 126)", "Date Added"],
      ["pubmed_id", "CONVERT(VARCHAR(20), pubmed_id)", "Pubmed Id or DOI"], 
      ["instrument_name","instrument_name","Instrument Name"],
      ["protease", "C.name", "Protease"],    
      ["sample_category", "SC.name", "Sample Category"],
      ["sample_category_id", "S.sample_category_id", "sample_category_id"]
    );

  #### Build the columns part of the SQL statement
  my %colnameidx = ();
  my @column_titles = ();
  my $columns_clause = $sbeams->build_SQL_columns_list(
    column_array_ref=>\@column_array,
    colnameidx_ref=>\%colnameidx,
    column_titles_ref=>\@column_titles
  );

  my $sql =qq~;
  select $columns_clause
  FROM $TBAT_SEARCH_BATCH_STATISTICS SBS 
  JOIN $TBAT_ATLAS_BUILD_SEARCH_BATCH ABSB ON ABSB.atlas_build_search_batch_id = SBS.atlas_build_search_batch_id
  JOIN $TBAT_ATLAS_SEARCH_BATCH ASB ON ( ASB.atlas_search_batch_id = ABSB.atlas_search_batch_id )
  JOIN $TBAT_SAMPLE S ON (S.sample_id = ASB.sample_id)
  LEFT JOIN $TBAT_SAMPLE_CATEGORY SC ON (S.sample_category_id = SC.id)
  LEFT JOIN (
		SELECT DISTINCT SAMPLE_ID, 
		STUFF(
			(SELECT DISTINCT ',' + CONVERT (VARCHAR , P.PUBMED_ID )
			FROM $TBAT_SAMPLE_PUBLICATION F2
			JOIN $TBAT_PUBLICATION P ON (P.PUBLICATION_ID = F2.PUBLICATION_ID AND F2.record_status != 'D')
      AND F1.SAMPLE_ID = F2.SAMPLE_ID
			FOR XML PATH ('')),1, 1, '' 
      ) AS Pubmed_ID
		FROM $TBAT_SAMPLE_PUBLICATION F1
  ) AS A ON (A.SAMPLE_ID = S.SAMPLE_ID) 
  JOIN PROTEOMICS.DBO.SEARCH_BATCH PSB  ON (PSB.SEARCH_BATCH_ID = ASB.PROTEOMICS_SEARCH_BATCH_ID)
  JOIN PROTEOMICS.DBO.PROTEOMICS_EXPERIMENT PE ON (PE.EXPERIMENT_ID = PSB.EXPERIMENT_ID)
  LEFT JOIN PROTEOMICS.DBO.INSTRUMENT I ON (I.INSTRUMENT_ID = PE.INSTRUMENT_ID)
  LEFT JOIN $TBAT_PROTEASES C ON (S.PROTEASE_ID = C.ID) 
  WHERE ABSB.atlas_build_id = $build_id
  AND ASB.record_status != 'D'
  AND ABSB.record_status != 'D'
  ORDER BY rownum, cumulative_n_peptides, ABSB.atlas_build_search_batch_id ASC
  ~;
  my @sample_info = $sbeams->selectSeveralColumns ( $sql );
  my (%unique_prot2sample_cnt, %unique_canprot2sample_cnt);
  $sql = qq~
   SELECT A.sample_id , count (distinct A.id)
   FROM (
		 SELECT sample_specific_id as sample_id, biosequence_id as id 
		 FROM $TBAT_PROTEIN_IDENTIFICATION 
		 WHERE 1 = 1
					 AND atlas_build_id IN ($build_id)
					 AND sample_specific_id is not null
		 UNION 
		 SELECT sample_specific_id as sample_id, related_biosequence_id as id 
		 FROM $TBAT_BIOSEQUENCE_RELATIONSHIP
		 WHERE 1 = 1
					 AND atlas_build_id IN ($build_id)
					 AND sample_specific_id is not null
   ) AS A
   GROUP BY A.sample_id
	~;
  %unique_prot2sample_cnt = $sbeams->selectTwoColumnHash($sql);
  $sql = qq~
     SELECT sample_specific_id , count(biosequence_id) 
     FROM $TBAT_PROTEIN_IDENTIFICATION
     WHERE 1 = 1
           AND atlas_build_id IN ($build_id)
           AND sample_specific_id is not null
           AND presence_level_id = 1
     GROUP BY sample_specific_id
  ~;
  %unique_canprot2sample_cnt = $sbeams->selectTwoColumnHash($sql);

  my (@samples);
  my $rownum = 0;
  for my $batch ( @sample_info ) {
    # if these aren't defined, set to zero
    for my $col_name (qw(n_uniq_contributed_peptides 
                    n_progressive_peptides 
                    cumulative_n_peptides
                    n_canonical_proteins
                    cumulative_n_proteins)){
        $batch->[$colnameidx{$col_name}] ||=0;
    }
    if ($rownum == 0){
      $batch->[$colnameidx{n_added_canonical_prots}] = $batch->[$colnameidx{n_canonical_proteins}];
    }else{
      $batch->[$colnameidx{n_added_canonical_prots}] = $batch->[$colnameidx{cumulative_n_proteins}] 
                                                       - $sample_info[$rownum-1]->[$colnameidx{cumulative_n_proteins}];
    } 
    for my $idx ( $colnameidx{'n_unique_prots'}) {
      if (defined $unique_prot2sample_cnt{$batch->[$colnameidx{sample_id}]}){
         $batch->[$idx] = $unique_prot2sample_cnt{$batch->[$colnameidx{sample_id}]};
      }else{
        $batch->[$idx] = '';
      }
    }
    for my $idx ( $colnameidx{'n_unique_canonical_prots'}) {
      if (defined $unique_canprot2sample_cnt{$batch->[$colnameidx{sample_id}]}){
         $batch->[$idx] = $unique_canprot2sample_cnt{$batch->[$colnameidx{sample_id}]};
      }else{
        $batch->[$idx] = '';
      }
    }
    push @samples, $batch;; 
    $rownum++;
  }

  for my $samp ( @samples ) {
    for my $col_name (qw
		      (n_runs
		       n_searched_spectra
		       n_good_spectra
		       n_distinct_peptides
		       n_uniq_contributed_peptides
		       n_progressive_peptides
		       cumulative_n_peptides
		       n_canonical_proteins
		       n_unique_canonical_prots
		       n_unique_prots
		       n_added_canonical_prots
		       cumulative_n_proteins)
	){
      $samp->[$colnameidx{$col_name}] = $sbeams->commifyNumber($samp->[$colnameidx{$col_name}]);
    }

  }
  unshift @samples, \@column_titles;
  return \@samples;
}

sub get_dataset_contrib_info {
  my $build_id = shift;
  #### Define some variables needed to build the query
  my @column_array = (
      ["repository_identifiers","repository_identifiers","Dataset"],
      ["n_runs","n_runs", "MS Runs"],
      ["n_searched_spectra", "n_searched_spectra", "Spectra Searched"],
      ["n_good_spectra", "n_good_spectra", "Spectra ID'd"],
      ["per_id", "CASE WHEN n_searched_spectra > 0 THEN FORMAT((n_good_spectra*1.00)/(n_searched_spectra/1.00), 'P2') ELSE '' END", "%Spectra ID'd"],
      ["n_distinct_peptides", "n_distinct_peptides","Distinct Peptides"],
      ["n_uniq_contributed_peptides", "n_uniq_contributed_peptides", "Unique Peptides"],
      ["n_progressive_peptides", "n_progressive_peptides", "Added Peptides"],
      ["cumulative_n_peptides", "cumulative_n_peptides", "Cumulative Peptides"],
      ["n_canonical_proteins", "n_canonical_proteins", "Distinct Canonical Proteins"],
      ["n_uniq_contributed_proteins", "n_uniq_contributed_proteins", "Unique All Proteins"],
      ["n_progressive_proteins", "n_progressive_proteins", "Added Canonical Proteins"],
      ["cumulative_n_proteins", "cumulative_n_proteins", "Cumulative Canonical Proteins"]
    );

  #### Build the columns part of the SQL statement
  my %colnameidx = ();
  my @column_titles = ();
  my $columns_clause = $sbeams->build_SQL_columns_list(
    column_array_ref=>\@column_array,
    colnameidx_ref=>\%colnameidx,
    column_titles_ref=>\@column_titles
  );

  my $sql =qq~;
  SELECT $columns_clause
  FROM $TBAT_DATASET_STATISTICS
  WHERE ATLAS_BUILD_ID = $build_id 
  ORDER BY rownum
  ~;
  my @info = $sbeams->selectSeveralColumns ( $sql );
  return [] if (! @info);
  for my $samp ( @info ) {
    for my $col_name (qw
		      (n_runs
		       n_searched_spectra
		       n_good_spectra
		       n_distinct_peptides
		       n_uniq_contributed_peptides
		       n_progressive_peptides
		       cumulative_n_peptides
		       n_canonical_proteins
		       n_uniq_contributed_proteins
		       n_progressive_proteins
		       cumulative_n_proteins)
	){
      $samp->[$colnameidx{$col_name}] = $sbeams->commifyNumber($samp->[$colnameidx{$col_name}]);
    }

  }
  unshift @info, \@column_titles;
  return \@info;
}

##################################################################################
### check protein existence in a dataset. 
##################################################################################
sub get_dataset_protein_info {
  my %args = @_;
  my $atlas_build_id = $args{build_id};

  my $sql = qq~
    SELECT biosequence_id, repository_identifiers 
    FROM $TBAT_BIOSEQUENCE_ID_ATLAS_BUILD_SEARCH_BATCH 
    WHERE atlas_build_id = $atlas_build_id 
  ~;
  
  my %biosequence_id_sample_id;
  my $sth = $sbeams->get_statement_handle( $sql );
  my ($biosequence_id, $repository_id);
  while( ($biosequence_id, $repository_id) = $sth->fetchrow_array() ) {
    $biosequence_id_sample_id{$biosequence_id}{$repository_id} =1;
  } 

  print "biosequence_id_sample_id keys=" . scalar keys %biosequence_id_sample_id;
  print "\n";
  $sql = qq~
		 SELECT BS.biosequence_id, BS.BIOSEQUENCE_NAME, PR.NAME
		 FROM $TBAT_BIOSEQUENCE BS 
     JOIN $TBAT_ATLAS_BUILD AB ON (AB.biosequence_set_id = BS.biosequence_set_id)
     JOIN (	
			 SELECT A.NAME, A.ID  
			 FROM (
				 SELECT PRL.LEVEL_NAME AS NAME,
								PID.biosequence_id as ID
				 FROM $TBAT_PROTEIN_IDENTIFICATION PID 
				 JOIN  $TBAT_PROTEIN_PRESENCE_LEVEL PRL
				 ON (PID.PRESENCE_LEVEL_ID = PRL.PROTEIN_PRESENCE_LEVEL_ID)
				 WHERE 1 = 1
							 AND atlas_build_id IN ($atlas_build_id)
				 UNION
				 SELECT BRT.RELATIONSHIP_NAME AS NAME, 
								BR.RELATED_BIOSEQUENCE_ID as ID 
				 FROM $TBAT_BIOSEQUENCE_RELATIONSHIP BR
				 JOIN $TBAT_BIOSEQUENCE_RELATIONSHIP_TYPE BRT
				 ON (BR.RELATIONSHIP_TYPE_ID = BRT.BIOSEQUENCE_RELATIONSHIP_TYPE_ID)
				 WHERE 1 = 1
							 AND atlas_build_id IN ($atlas_build_id)
			 ) AS A ) PR  ON (PR.ID = BS.biosequence_id) 
     WHERE 1 = 1
         AND AB.atlas_build_id = $atlas_build_id
          AND BS.BIOSEQUENCE_ID NOT IN (
            SELECT BR.RELATED_BIOSEQUENCE_ID
             FROM $TBAT_BIOSEQUENCE_RELATIONSHIP BR
             WHERE RELATIONSHIP_TYPE_ID = 2
          )
  ~;

  my %dataset_prot_cnt;
  my $possibly_distinguished = 0;
  my $noncore_canonical = 0;
  my $sth = $sbeams->get_statement_handle( $sql );
  while( my $row = $sth->fetchrow_arrayref() ) {
    my ($bs_id, $bs_name,$protein_level ) =@$row;
    next if ($bs_name =~ /(decoy|contam)/i);
    foreach my $repository_id (keys %{$biosequence_id_sample_id{$bs_id}}){
			if ($protein_level =~ /possibly_distinguished/i){
				 $possibly_distinguished++;
			}
			if ($protein_level =~ /noncore/){
				 $noncore_canonical =1;
			}
      
			$dataset_prot_cnt{$repository_id}{$protein_level}{$bs_name} =1;
    }
  }
  ## older builds, skip
  return [] if ($possibly_distinguished > 0);
  return [] if (scalar keys %dataset_prot_cnt == 0);
  my $sql =qq~;
    SELECT LEVEL_NAME AS NAME, PROTEIN_PRESENCE_LEVEL_ID AS ID
    FROM $TBAT_PROTEIN_PRESENCE_LEVEL
    UNION
    SELECT RELATIONSHIP_NAME AS NAME, BIOSEQUENCE_RELATIONSHIP_TYPE_ID AS ID
    FROM $TBAT_BIOSEQUENCE_RELATIONSHIP_TYPE
  ~;
  my %protein_level_ids = $sbeams->selectTwoColumnHash($sql);

  my @level_names = ('canonical','indistinguishable representative'  ,'representative'
                     ,'marginally distinguished','weak','insufficient evidence'); 
  if ($noncore_canonical){
    splice @level_names, 1, 0, 'noncore-canonical';
  }

  my @headings =('Dataset',@level_names);
  my @sortable=();
  my @align=();
  for my $col ( @headings ) {
    $col =~ s/(\w+)/\u$1/g;
    push @sortable, $col,$col;
    push @align, 'center';
  }
  $align[0] = 'left';
  my @records = ();
  foreach my $repository_id (sort {$a cmp $b} keys %dataset_prot_cnt){
    my @row =();
    push @row , $repository_id; 
    foreach my $level_name (@level_names){
      my $cnt = scalar keys %{$dataset_prot_cnt{$repository_id}{$level_name}} || 0;
      if ( $cnt){
         push @row , $cnt;
      }else{
         push @row ,'';
      }
    }
    push @records, \@row;
  }
  unshift  @records, \@headings;
  return \@records;
}
sub get_dataset_protein_info_old {
  my %args = @_;
  my $atlas_build_id = $args{build_id};
  my $sql =qq~;
    SELECT S.SAMPLE_ID, S.REPOSITORY_IDENTIFIERS, ABSB.ATLAS_BUILD_SEARCH_BATCH_ID
    FROM $TBAT_SAMPLE  S
    JOIN $TBAT_ATLAS_BUILD_SEARCH_BATCH ABSB ON (S.sample_id = ABSB.sample_id)
    JOIN $TBAT_ATLAS_SEARCH_BATCH ASB ON (ASB.ATLAS_SEARCH_BATCH_ID = ABSB.ATLAS_SEARCH_BATCH_id)
    WHERE REPOSITORY_IDENTIFIERS IS NOT NULL
    AND ABSB.atlas_build_id = $atlas_build_id
    AND ASB.record_status != 'D'
    AND REPOSITORY_IDENTIFIERS != ''
  ~;

  my %sample_repository_ids = ();
  my %absb2sample_id =();
   my @rows = $sbeams->selectSeveralColumns($sql);
  foreach my $row(@rows){
    my ($sample_id,$repository_id, $absb_id) = @$row;
    $absb2sample_id{$absb_id} = $sample_id; 
    $sample_repository_ids{$sample_id} = $repository_id;
  }

  print "sample_ids=". scalar keys %sample_repository_ids;
  print "\n";

  my $join = '';
  if ($TBAT_BIOSEQUENCE_ID_ATLAS_BUILD_SEARCH_BATCH =~ /peptideatlas_2/i){
    $join = qq~
     JOIN $TBAT_ATLAS_BUILD_SEARCH_BATCH ABSB
     ON (ABSB.ATLAS_BUILD_SEARCH_BATCH_ID = BIABSB.ATLAS_BUILD_SEARCH_BATCH_ID)
     JOIN $TBAT_ATLAS_SEARCH_BATCH ASB ON (ASB.ATLAS_SEARCH_BATCH_ID = ABSB.ATLAS_SEARCH_BATCH_id)
     WHERE ABSB.atlas_build_id = $atlas_build_id
     AND ASB.record_status != 'D'
    ~;
  }
  $sql = qq~
    SELECT BIABSB.biosequence_id, BIABSB.ATLAS_BUILD_SEARCH_BATCH_ID 
    FROM $TBAT_BIOSEQUENCE_ID_ATLAS_BUILD_SEARCH_BATCH BIABSB
    $join
  ~;
  
  my %biosequence_id_sample_id;
  my $sth = $sbeams->get_statement_handle( $sql );
  my ($biosequence_id, $absb_id);
  while(($biosequence_id, $absb_id) = $sth->fetchrow_array() ) {
    $biosequence_id_sample_id{$biosequence_id}{$absb2sample_id{$absb_id}} =1;
  } 

  print "biosequence_id_sample_id keys=" . scalar keys %biosequence_id_sample_id;
  print "\n";
  $sql = qq~
		 SELECT BS.biosequence_id, BS.BIOSEQUENCE_NAME, PR.NAME
		 FROM $TBAT_BIOSEQUENCE BS 
     JOIN $TBAT_ATLAS_BUILD AB ON (AB.biosequence_set_id = BS.biosequence_set_id)
     JOIN (	
			 SELECT A.NAME, A.ID  
			 FROM (
				 SELECT PRL.LEVEL_NAME AS NAME,
								PID.biosequence_id as ID
				 FROM $TBAT_PROTEIN_IDENTIFICATION PID 
				 JOIN  $TBAT_PROTEIN_PRESENCE_LEVEL PRL
				 ON (PID.PRESENCE_LEVEL_ID = PRL.PROTEIN_PRESENCE_LEVEL_ID)
				 WHERE 1 = 1
							 AND atlas_build_id IN ($atlas_build_id)
				 UNION
				 SELECT BRT.RELATIONSHIP_NAME AS NAME, 
								BR.RELATED_BIOSEQUENCE_ID as ID 
				 FROM $TBAT_BIOSEQUENCE_RELATIONSHIP BR
				 JOIN $TBAT_BIOSEQUENCE_RELATIONSHIP_TYPE BRT
				 ON (BR.RELATIONSHIP_TYPE_ID = BRT.BIOSEQUENCE_RELATIONSHIP_TYPE_ID)
				 WHERE 1 = 1
							 AND atlas_build_id IN ($atlas_build_id)
			 ) AS A ) PR  ON (PR.ID = BS.biosequence_id) 
     WHERE 1 = 1
         AND AB.atlas_build_id = $atlas_build_id
          AND BS.BIOSEQUENCE_ID NOT IN (
            SELECT BR.RELATED_BIOSEQUENCE_ID
             FROM $TBAT_BIOSEQUENCE_RELATIONSHIP BR
             WHERE RELATIONSHIP_TYPE_ID = 2
          )
  ~;
  my %dataset_prot_cnt;
  my $possibly_distinguished = 0;
  my $noncore_canonical = 0;
  my $sth = $sbeams->get_statement_handle( $sql );
  while( my $row = $sth->fetchrow_arrayref() ) {
    my ($bs_id, $bs_name,$protein_level ) =@$row;
    next if ($bs_name =~ /(decoy|contam)/i);
    foreach my $sample_id (keys %{$biosequence_id_sample_id{$bs_id}}){
			if ($protein_level =~ /possibly_distinguished/i){
				 $possibly_distinguished++;
			}
			if ($protein_level =~ /noncore/){
				 $noncore_canonical =1;
			}
			$dataset_prot_cnt{$sample_repository_ids{$sample_id}}{$protein_level}{$bs_name} =1;
    }
  }
  ## older builds, skip
  return [] if ($possibly_distinguished > 0);
  return [] if (scalar keys %dataset_prot_cnt == 0);
  my $sql =qq~;
    SELECT LEVEL_NAME AS NAME, PROTEIN_PRESENCE_LEVEL_ID AS ID
    FROM $TBAT_PROTEIN_PRESENCE_LEVEL
    UNION
    SELECT RELATIONSHIP_NAME AS NAME, BIOSEQUENCE_RELATIONSHIP_TYPE_ID AS ID
    FROM $TBAT_BIOSEQUENCE_RELATIONSHIP_TYPE
  ~;
  my %protein_level_ids = $sbeams->selectTwoColumnHash($sql);

  my @level_names = ('canonical','indistinguishable representative'  ,'representative'
                     ,'marginally distinguished','weak','insufficient evidence'); 
  if ($noncore_canonical){
    splice @level_names, 1, 0, 'noncore-canonical';
  }

  my @headings =('Dataset',@level_names);
  my @sortable=();
  my @align=();
  for my $col ( @headings ) {
    $col =~ s/(\w+)/\u$1/g;
    push @sortable, $col,$col;
    push @align, 'center';
  }
  $align[0] = 'left';
  my @records = ();
  foreach my $repository_id (sort {$a cmp $b} keys %dataset_prot_cnt){
    my @row =();
    push @row , $repository_id; 
    foreach my $level_name (@level_names){
      my $cnt = scalar keys %{$dataset_prot_cnt{$repository_id}{$level_name}} || 0;
      if ( $cnt){
         push @row , $cnt;
      }else{
         push @row ,'';
      }
    }
    push @records, \@row;
  }
  unshift  @records, \@headings;
  return \@records;
}


sub get_build_path {
  my %args = @_;
  return unless $args{build_id};
  my $path = $atlas->getAtlasBuildDirectory( atlas_build_id => $args{build_id} );
  $path =~ s/DATA_FILES//;
  return $path;
}

sub add_thousand_separator {
 my $num = shift;
 my $formated_num = $num;
 if ($num =~ /^\d+$/){
		while ($num =~ s/^(-?\d+)(\d{3}(?:,\d{3})*(?:\.\d+)*)$/$1,$2/){};
		$formated_num = $num;
 }elsif($num =~ /^(\d+)\s([\(\)\d\.\%]+)$/){
		 $num = $1;
		 my $pect = $2;
		 while ($num =~ s/^(-?\d+)(\d{3}(?:,\d{3})*(?:\.\d+)*)$/$1,$2/){};
		 $formated_num = "$num $pect";
	}
  return $formated_num;
}
