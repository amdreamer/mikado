import sys,os.path
from mikado_lib.loci_objects.transcript import Transcript
#from mikado_lib.exceptions import NotInLocusError
sys.path.append(os.path.dirname(os.path.dirname(__file__)))
#from mikado_lib.mikado_lib.Excluded import Excluded
from mikado_lib.loci_objects.abstractlocus import Abstractlocus
from mikado_lib.loci_objects.sublocus import Sublocus
from mikado_lib.loci_objects.locus import locus
from mikado_lib.loci_objects.monosublocus import Monosublocus

#Resolution order is important here!
class monosublocus_holder(Sublocus,Abstractlocus):
    
    '''This is a container that groups together the transcripts surviving the selection for the Monosublocus.
    The class inherits from both sublocus and Abstractlocus (the main abstract class) in order to be able to reuse
    some of the code present in the former.
    Internally, the most important method is define_loci - which will select the best transcript(s) and remove all the overlapping ones.
    The intersection function for this object is quite laxer than in previous stages, and so are the requirements for the inclusion.
    '''

    __name__ = "monosubloci_holder"

    def __init__(self, monosublocus_instance: Monosublocus, json_dict=None, logger=None):
        
        Abstractlocus.__init__(self)
        self.set_logger(logger)
        self.splitted=False
        self.metrics_calculated = False
        self.json_dict = json_dict
        self.excluded=None
        self.purge = self.json_dict["run_options"]["purge"]
        self.scores_calculated=False
        #Add the transcript to the locus
        self.locus_verified_introns=set()
        self.add_monosublocus(monosublocus_instance)
        
        

    def add_transcript_to_locus(self, transcript, check_in_locus = True):
        '''Override of the sublocus method, and reversal to the original method in the Abstractlocus class.
        The check_in_locus boolean flag is used to decide whether to check if the transcript is in the locus or not.
        This should be set to False for the first transcript, and True afterwards.'''
#         if check_in_locus is True:
#             check = self.in_locus(self, transcript_instance)
#             if check is False:
#                 raise NotInLocusError()
#         
        Abstractlocus.add_transcript_to_locus(self, transcript, check_in_locus=True)
        self.locus_verified_introns = set.union(self.locus_verified_introns, transcript.verified_introns)
            
    def add_monosublocus(self, monosublocus_instance: Monosublocus):
        '''Wrapper to extract the transcript from the monosubloci and pass it to the constructor.'''
        assert len(monosublocus_instance.transcripts)==1
        if len(self.transcripts)==0:
            check_in_locus = False
        else:
            check_in_locus = True
        for tid in monosublocus_instance.transcripts:
            self.add_transcript_to_locus(monosublocus_instance.transcripts[tid], check_in_locus=check_in_locus)
            
    def __str__(self):
        '''This special method is explicitly *not* implemented; this locus object is not meant for printing, only for computation!'''
        raise NotImplementedError("This is a container used for computational purposes only, it should not be printed out directly!")
        
    def define_monosubloci(self):
        '''Overriden and set to NotImplemented to avoid cross-calling it when inappropriate.'''
        raise NotImplementedError("Monosubloci are the input of this object, not the output.")
    
    def define_loci(self, purge=False, excluded=None):
        '''This is the main function of the class. It is analogous to the define_subloci class defined
        for sublocus objects, but it returns "locus" objects (not "Monosublocus").'''
        if self.splitted is True:
            return
        
        self.loci=[]
#         remaining = self.transcripts.copy()
        self.excluded = excluded
        
        self.calculate_scores()
        
        graph = self.define_graph(self.transcripts, inters=self.is_intersecting,
                                  cds_only=self.json_dict["run_options"]["subloci_from_cds_only"]) 
        
        while len(graph)>0:
            cliques, communities = self.find_communities(graph)
            to_remove = set()
            for lc in communities:
                lc = dict((x, self.transcripts[x]) for x in lc)
                selected_tid=self.choose_best(lc)
                selected_transcript = self.transcripts[selected_tid]
                to_remove.add(selected_tid)
                for clique in cliques:
                    if selected_tid in clique:
                        to_remove.update(clique)
                
                if purge is False or selected_transcript.score>0:
                    new_locus = locus(selected_transcript, logger=self.logger)
                    self.loci.append(new_locus)
            self.logger.debug("Removing {0} transcripts from {1}".format(len(to_remove), self.id))
            graph.remove_nodes_from(to_remove) #Remove nodes from graph, iterate
        
        self.splitted = True
        return

    @classmethod
    def is_intersecting(cls, transcript_instance, other, cds_only=False):
        '''
        Implementation of the is_intersecting method. Now that we are comparing transcripts that
        by definition span multiple subloci, we have to be less strict in our definition of what
        counts as an intersection.
        Criteria:
        - 1 splice site in common (splice, not junction)
        - If one or both of the transcript is monoexonic OR one or both lack an ORF, check for any exonic overlap
        - Otherwise, check for any CDS overlap. 
        '''
        if transcript_instance.id==other.id:
            return False # We do not want intersection with oneself

        if cls.overlap((transcript_instance.start,transcript_instance.end), (other.start,other.end) )<=0: return False
        if cds_only is False:
            if len(set.intersection( set(transcript_instance.splices), set(other.splices)))>0:
                return True
        else:
            transcript_splices = set()
            other_splices = set()
            for intron in transcript_instance.combined_cds_introns:
                transcript_splices.add(intron[0])
                transcript_splices.add(intron[1])
            for intron in other.combined_cds_introns:
                other_splices.add(intron[0])
                other_splices.add(intron[1])
            if len(set.intersection( transcript_splices, other_splices))>0:
                return True
        
        if other.monoexonic is True or transcript_instance.monoexonic is True or \
            min(other.combined_cds_length,transcript_instance.combined_cds_length)==0:
                for exon in transcript_instance.exons:
                    for oexon in other.exons:
                        if cls.overlap(exon, oexon) >= 0:
                            return True

        for cds_segment in transcript_instance.combined_cds:
            for ocds_segment in other.combined_cds:
                if cls.overlap(cds_segment,ocds_segment)>0:
                    return True
        
        return False

    @classmethod
    def in_locus(cls, locus_instance: Abstractlocus, transcript_instance: Transcript, flank=0) -> bool:
        '''This method checks whether a transcript / monosbulocus falls inside the locus coordinates.'''
        if hasattr(transcript_instance, "transcripts"):
            assert len(transcript_instance.transcripts)==1
            transcript_instance = transcript_instance.transcripts[list(transcript_instance.transcripts.keys())[0]]
            assert hasattr(transcript_instance,"finalize")
        is_in_locus = Abstractlocus.in_locus(locus_instance, transcript_instance, flank=flank)
        if is_in_locus is True:
            is_in_locus=False
            for tran in locus_instance.transcripts:
                tran=locus_instance.transcripts[tran]
                is_in_locus = cls.is_intersecting(tran, transcript_instance)
                if is_in_locus is True: break
        return is_in_locus
    
    @property
    def id(self):
        return Abstractlocus.id.fget(self)  # @UndefinedVariable