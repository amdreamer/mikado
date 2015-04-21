from abstractlocus import abstractlocus
import random,sys,operator
from copy import copy
from locus import locus
import transcript

class sublocus(abstractlocus):
    
    '''
    The sublocus class is created either by the superlocus class during the subloci definition, or directly using a G(T|F)line-like object.
    It is used to define the final loci.
    '''
    
    def __init__(self, span):
        
        '''This '''
        
        self.transcripts = set()
        self.fixedSize=True if span.feature=="sublocus" else False
        self.feature="sublocus"
        self.splices = set()
        self.junctions = set()
        self.metrics=dict()
        self.splitted=False
        self.exons=set()
        self.stranded=True

        #Copy attributes into the current dictionary
        for key in ["parent", "id", "start", "end", "chrom", "strand", "attributes"]:
            setattr(self, key, getattr(span, key))
        
        setattr( self, "monoexonic", getattr(span, "monoexonic", None)  )
        
        if span.feature=="transcript" or "RNA" in span.feature.upper():
            self.add_transcript_to_locus(span)
        
    
    def add_transcript_to_locus(self, transcript):
        if transcript is None: return
        transcript.finalize()
        if self.monoexonic is None:
            self.monoexonic = transcript.monoexonic
        elif self.monoexonic!=transcript.monoexonic:
            raise ValueError("Sublocus and transcript are not compatible!\n{0}\t{1}\t{2}\t{3}\t{4}\n{5}".format(self.chrom,
                                                                                                           self.start,
                                                                                                           self.end,
                                                                                                           self.strand,
                                                                                                           self.monoexonic,
                                                                                                           transcript))
        super().add_transcript_to_locus(transcript)
        self.exons = set.union(self.exons, transcript.exons)
        self.metrics[transcript.id]=dict()
    
    @property
    def splitted(self):
        '''The splitted flag indicates whether a sublocus has already been processed to produce the necessary loci.
        It must be set as a boolean flag (hence why it is coded as a property)'''
        return self.__splitted
    
    @splitted.setter
    def splitted(self,verified):
        if type(verified)!=bool:
            raise TypeError()
        self.__splitted=verified
    
    @classmethod
    def is_intersecting(cls, transcript, other):
        '''
        Implementation of the is_intersecting method. Here at the level of the sublocus,
        the intersection is seen as overlap between exons. 
        '''
          
        if transcript.id==other.id: return False # We do not want intersection with oneself
        for exon in transcript.exons:
            if any(
                   filter(
                          #Check that at least one couple of exons are overlapping
                          lambda oexon: cls.overlap( exon, oexon )>=0, 
                          other.exons
                          )
                   ) is True:
                return True
        
        return False
        
    
    def define_loci(self):
         
        self.loci=[]
        best_tid,best_score=self.choose_best(self.metrics)
        best_transcript=next(filter(lambda x: x.id==best_tid, self.transcripts))
        best_transcript.score=best_score
        new_locus = locus(best_transcript)
        self.loci.append(new_locus)
        remaining = self.transcripts.copy()
        remaining.remove(best_transcript)
        not_intersecting=set(filter(lambda x: not self.is_intersecting(best_transcript, x), remaining ))
        
        while len(not_intersecting)>0:
            metrics=dict((tid, self.metrics[tid]) for tid in self.metrics if tid in [ trans.id for trans in not_intersecting ]  )
            best_tid,best_score=self.choose_best(metrics)
            best_transcript=next(filter(lambda x: x.id==best_tid, not_intersecting))
            new_locus = locus(best_transcript)
            self.loci.append(new_locus)
            remaining = not_intersecting.copy()
            remaining.remove(best_transcript)
            not_intersecting=set(filter(lambda x: not self.is_intersecting(best_transcript, x), remaining ))
    
        self.splitted=True
        return
    
    
    def calculate_metrics(self, tid):
        '''This function will calculate the metrics which will be used to derive a score for a transcript.
        The different attributes of the transcript will be stored inside the transcript class itself,
        to be more precise, into an internal dictionary ("metrics").
        One thing - this metrics dictionary is potentially a memory drag as I am replicating various attributes, for convenience.
        Another detail - as I need transcripts to be held in a set rather than a dictionary, for most cases,
        I have to remove the transcript I am analyzing from the "transcripts" store and readd it later after calculating the metrics .. 
         
        The scoring function must consider the following factors:
        - "exons":              No. of exons 
        - "exon_frac":          % of exons on the total of the exons of the sublocus
        - "intron_frac":        % of introns on the total of the intronts of the sublocus
        - "retained_introns":   no. of retained introns (see has_retained_introns)
        - "retained_frac":      % of cdna_length that is in retained introns 
        - "cds_length":         length of the CDS
        - "cds_fraction":       length of the CDS/length of the cDNA
        - "internal_cds_num":   number of internal CDSs. 1 is top, 0 is worst, each number over 1 is negative.             
        - "max_internal_cds_exon_num":   number of CDS exons present in the longest ORF.
        - "max_internal_cds_length":     length of the greatest CDS
        - "max_internal_cds_fraction":   fraction of the cDNA which is in the maximal CDS
        - "cds_not_maximal":            length of CDS *not* in the maximal ORF
        - "cds_not_maximal_fraction"    fraction of CDS *not* in the maximal ORF 
        '''
    
        transcript_instance = next(filter( lambda t: t.id==tid, self.transcripts))
        self.transcripts.remove(transcript_instance)
        transcript_instance.finalize() # The transcript must be finalized before we can calculate the score.
        
        transcript_instance.metrics["exons"]=len(transcript_instance.exons)
        transcript_instance.metrics["exon_frac"] = len(set.intersection( self.exons,transcript_instance.exons   ))/len(self.exons)
        if len(self.junctions)>0:
            transcript_instance.metrics["intron_frac"] = len(set.intersection( self.junctions,transcript_instance.junctions   ))/len(self.junctions)
        else:
            transcript_instance.metrics["intron_frac"]=None
        self.find_retained_introns(transcript_instance)
        transcript_instance.metrics["retained_introns"] = len(transcript_instance.retained_introns)
        transcript_instance.metrics["retained_frac"]=sum(e[1]-e[0]+1 for e in transcript_instance.retained_introns)/transcript_instance.cdna_length
        transcript_instance.metrics["cds_exons"] = len(transcript_instance.cds)
        transcript_instance.metrics["cds_length"] = transcript_instance.cds_length
        transcript_instance.metrics["cds_fraction"] = transcript_instance.cds_length/transcript_instance.cdna_length
        transcript_instance.metrics["internal_cds_num"] = transcript_instance.internal_cds_num
        transcript_instance.metrics["max_internal_cds_num"] = len(transcript_instance.max_internal_cds)
        transcript_instance.metrics["max_internal_cds_length"] = transcript_instance.max_internal_cds_length
        transcript_instance.metrics["max_internal_cds_fraction"] = transcript_instance.max_internal_cds_length/transcript_instance.cdna_length
        transcript_instance.metrics["cds_not_maximal"] = transcript_instance.cds_length - transcript_instance.max_internal_cds_length
        if transcript_instance.max_internal_cds_length>0:
            transcript_instance.metrics["cds_not_maximal_fraction"] = (transcript_instance.cds_length - transcript_instance.max_internal_cds_length)/transcript_instance.cds_length
        else:
            transcript_instance.metrics["cds_not_maximal_fraction"] = 0
        transcript_instance.metrics["cdna_length"] = transcript_instance.cdna_length
        self.transcripts.add(transcript_instance)
        
        
    def find_retained_introns(self, transcript_instance):
         
        '''This method checks the number of exons that are possibly retained introns for a given transcript.
        To perform this operation, it checks for each exon whether it exists a sublocus intron that
        is *completely* contained within a transcript exon.
        The results are stored inside the transcript instance, in the "retained_introns" tuple.'''
         
        transcript_instance.retained_introns=[]
        for exon in transcript_instance.exons:
            #Check that the overlap is at least as long as the minimum between the exon and the intron.
            if any(filter(
                          lambda junction: self.overlap(exon,junction)>=min(junction[1]-junction[0]+1, exon[1]-exon[0]+1),
                          self.junctions                          
                          )) is True:
                transcript_instance.retained_introns.append(exon)
        transcript_instance.retained_introns=tuple(transcript_instance.retained_introns)
            
    def load_scores(self, scores):
        '''Simple mock function to load scores for the transcripts from a tab-delimited file.
        This implementation will have to be rewritten for the final pipeline.
        Moreover, this is potentially a disk-killer - each sublocus will have to parse the whole shebang!
        It will probably be much better to write down everything in a SQLite DB, or parse it separately once
        and write a "connector" to the global dictionary. Or something.
        '''
        
        for tid in filter(lambda tid: tid in self.metrics, scores):
            self.metrics[tid]["score"]=scores[tid]
        
        #Using the _ as variable because it is ignored by checks for used variables
        try: 
            if sum([1 for _ in filter(lambda tid: "score" in self.metrics[tid], self.metrics  )])!=len(self.metrics):
                raise ValueError("I have not been able to find a score for all of the transcripts!")
        except TypeError as err:
            raise TypeError("{0}\n{1}".format(err, self.metrics) )
            
            
    def calculate_scores(self, maximum_utr=3, minimum_cds_fraction=0.5, order=("intron_frac", "cds_length")):
        '''Function to calculate a score for each transcript, given the metrics derived
         with the calculate_metrics method.
         Keyword arguments:
         
         - maximum_utr                Maximum number of UTR exons
         - minimum_cds_fraction       How much of the cdna should be CDS, at a minimum
         '''
        
        self.metrics=dict()
        score=0
        
        for transcript in self.transcripts:
            self.calculate_metrics(transcript.id)
        
        def keyfunction(transcript_instance, order=[]   ):
            if len(order)==0:
                raise ValueError("No information on how to sort!")
            return tuple([transcript_instance.metrics[x] for x in order])
        
        current_score=0
        
        for transcript_instance in sorted( self.transcripts, key=lambda item: keyfunction(item, order=order)):
            self.metrics[transcript_instance.id]=copy(transcript_instance.metrics)
            if len(transcript_instance.utr)>maximum_utr or self.metrics[transcript_instance.id]["cds_fraction"]<minimum_cds_fraction:
                score=float("-Inf")
            else:
                score=current_score
                current_score+=1
            self.metrics[transcript_instance.id]["score"]=score
         
        return
    
    @classmethod
    def choose_best(cls, metrics):
        best_score,best_tid=float("-Inf"),[]
        for tid in metrics:
            score=metrics[tid]["score"]
            if score>best_score:
                best_score,best_tid=score,[tid]
            elif score==best_score:
                best_tid.append(tid)
        if len(best_tid)!=1:
            if len(best_tid)==0:
                raise ValueError("Odd. I have not been able to find the transcript with the best score: {0}".format(best_score))
            else:
                print("WARNING: multiple transcripts with the same score ({0}). I will choose one randomly.".format(", ".join(best_tid)
                                                                                                                    ) , file=sys.stderr)
                best_tid=random.sample(best_tid, 1) #this returns a list
        best_tid=best_tid[0]
        return best_tid, best_score
    
    def __str__(self):
        
        if self.strand is not None:
            strand=self.strand
        else:
            strand="."
        
        lines=[]
        
        if self.splitted is False:
            attr_field="ID={0};Parent={1};multiexonic={2}".format(
                                                              self.id,
                                                              self.parent,
                                                              str(not self.monoexonic)
                                                            )
                            
            self_line = [ self.chrom, "locus_pipeline", "sublocus", self.start, self.end,
                     ".", strand, ".", attr_field]
            lines.append("\t".join([str(s) for s in self_line]))
        
            transcripts = iter(sorted(self.transcripts, key=operator.attrgetter("start", "end")))
            for transcript in transcripts:
                transcript.parent=self.id
                lines.append(str(transcript).rstrip())
                
        else:
            for slocus in sorted(self.loci): #this should function ... I have implemented the sorting in the class ...
                lines.append(str(slocus).rstrip())
                
        return "\n".join(lines)
        
        
        
        
    