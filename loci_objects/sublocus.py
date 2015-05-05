from loci_objects.abstractlocus import abstractlocus
#import random
#from copy import copy
from loci_objects.monosublocus import monosublocus
from loci_objects.transcript import transcript
import os
from loci_objects.GFF import gffLine

class sublocus(abstractlocus):
    
    '''
    The sublocus class is created either by the superlocus class during the subloci definition, or directly using a G(T|F)line-like object.
    It is used to define the final monosubloci.
    '''
    
    @staticmethod
    def get_metrics_names():
        '''Static method to retrieve the available metrics from the metrics.txt
        file, only when the class is called for the first time.
        The method also checks that the requested metrics are defined as
        properties of the transcript class; if that is not the case, it raises
        an exception.'''
        
        __available_metrics = [l.rstrip() for l in open(
                                              os.path.join(
                                                           os.path.dirname(__file__),
                                                           "metrics.txt"
                                                           )
                                              )]
        first = ["tid","parent","score"];
        extended=[]
        not_found = []
        not_properties=[]
        for x in __available_metrics:
            if x=='': continue
            if x not in first:
                if not hasattr(transcript, x):
                    not_found.append(x)
                elif not type(transcript.__dict__[x]) is property: # @UndefinedVariable
                    not_properties.append(x)
                extended.append(x)
        if len(not_found)>0 or len(not_properties)>0:
            err_message=''
            if len(not_found)>0:
                err_message+="The following required metrics are not defined.\n\t{0}\n".format(
                                                                                                                 "\n\t".join(not_found)
                                                                                                                 )
            if len(not_properties)>0:
                err_message+="""The following metrics are not properties but rather
                methods of the transcript class. I cannot use them properly.
                \t{0}
                """.format("\n\t".join(not_properties))
            raise AttributeError(err_message)
        __available_metrics=first
        __available_metrics.extend(sorted(extended))
        return __available_metrics
    
    __name__ = "sublocus"
    available_metrics = []
    if available_metrics == []:
        available_metrics = get_metrics_names.__func__()
    
    ################ Class special methods ##############
    
    def __init__(self, span, source=None, json_dict = None ):
        
        '''This class takes as input a "span" feature - e.g. a gffLine or a transcript_instance. 
        The span instance should therefore have such attributes as chrom, strand, start, end, attributes. '''
        super().__init__()
        
        self.fixedSize=True if span.feature=="sublocus" else False
        self.feature="sublocus"
        if source is not None:
            self.source = source
        else:
            self.source = "locus_pipeline"
        self.splitted=False
        self.metrics_calculated=False #Flag to indicate that we have not calculated the metrics for the transcripts
        setattr( self, "monoexonic", getattr(span, "monoexonic", None)  )
        if json_dict is None or type(json_dict) is not dict:
            raise ValueError("I am missing the configuration for prioritizing transcripts!")
        self.json_dict = json_dict
        
        #This part is necessary to import modules
        if "modules" in self.json_dict:
            import importlib
            for mod in self.json_dict["modules"]:
                globals()[mod]=importlib.import_module(mod)
        
        #assert hasattr(self, "monoexonic")

        if type(span) is transcript:
            self.add_transcript_to_locus(span)
        else:
            for key in ["parent", "start", "end", "chrom", "strand", "attributes"]:
                setattr(self, key, getattr(span, key))
        
        
    def __str__(self):
        
        lines=[]
        
        if self.splitted is False:

            self_line=gffLine('')
            for attr in ["chrom", 'feature','source','start','end','strand']:
                setattr(self_line,attr, getattr(self,attr))
            self_line.phase,self_line.score=None,None
            self_line.id=self.id
            self_line.name=self.name
            self_line.parent=self.parent
            self_line.attributes["multiexonic"]=(not self.monoexonic)
            lines.append(str(self_line))
        
            for tid in sorted(self.transcripts, key=lambda tid: self.transcripts[tid]):
                self.transcripts[tid].source=self.source
                lines.append(str(self.transcripts[tid]).rstrip())
        else:
            for slocus in sorted(self.monosubloci): 
                lines.append(str(slocus).rstrip())
        
        return "\n".join(lines)

    
    ########### Class instance methods #####################
    
    def add_transcript_to_locus(self, transcript_instance):
        
        '''This is an override of the original method, as at the sublocus stage we need to accomplish a couple of things more:
        - check that transcripts added to the sublocus are either all monoexonic or all multiexonic
        - change the id of the transcripts to  
        '''
        
        if transcript_instance is None: return
        assert hasattr(self, "monoexonic")
        if self.initialized is False:
            self.monoexonic = transcript_instance.monoexonic
        elif self.monoexonic!=transcript_instance.monoexonic:
            raise ValueError("Sublocus and transcript are not compatible!\n{0}\t{1}\t{2}\t{3}\t{4}\n{5}".format(self.chrom,
                                                                                                           self.start,
                                                                                                           self.end,
                                                                                                           self.strand,
                                                                                                           self.monoexonic,
                                                                                                           transcript))

        super().add_transcript_to_locus(transcript_instance)
        
        #Update the id

    def define_monosubloci(self, purge=False):
        '''This function retrieves the best non-overlapping transcripts inside the sublocus, according to the score
        calculated by calculate_scores (explicitly called inside the method).'''
        
        self.monosubloci=[]
        self.calculate_scores()
        remaining = self.transcripts.copy()
        
        while len(remaining)>0:
            assert len(remaining)>0
            best_tid=self.choose_best(remaining.copy())
            best_transcript = remaining[best_tid]
            new_remaining = remaining.copy()
            del new_remaining[best_tid]
            for tid in remaining:
                if tid==best_tid: continue
                if self.is_intersecting(best_transcript, new_remaining[tid]):
                    del new_remaining[tid]
            if best_transcript.score==0 and purge is True:
                pass
            else:
                new_locus = monosublocus(best_transcript)
                self.monosubloci.append(new_locus)
                    
            remaining=new_remaining.copy()
            if len(remaining)==0: break
            
        self.splitted=True
        return
    
   
    def calculate_metrics(self, tid):
        '''This function will calculate the metrics for a transcript which are relative in nature
        i.e. that depend on the other transcripts in the sublocus. Examples include the fraction
        of introns or exons in the sublocus, or the number/fraction of retained introns.  
        '''
    
        transcript_instance = self.transcripts[tid]
        self.transcripts[tid].finalize() # The transcript must be finalized before we can calculate the score.
        
        self.transcripts[tid].exon_fraction = len(set.intersection( self.exons,self.transcripts[tid].exons   ))/len(self.exons)
        if len(self.junctions)>0:
            transcript_instance.intron_fraction = len(set.intersection( self.junctions,transcript_instance.junctions   ))/len(self.junctions)
        else:
            transcript_instance.intron_fraction = 0
        self.find_retained_introns(transcript_instance)
        transcript_instance.retained_fraction=sum(e[1]-e[0]+1 for e in transcript_instance.retained_introns)/transcript_instance.cdna_length
        self.transcripts[tid]=transcript_instance
        
    def find_retained_introns(self, transcript_instance):
         
        '''This method checks the number of exons that are possibly retained introns for a given transcript.
        To perform this operation, it checks for each non-CDS exon whether it exists a sublocus intron that
        is *completely* contained within a transcript exon.
        CDS exons are ignored because their retention might be perfectly valid.
        The results are stored inside the transcript instance, in the "retained_introns" tuple.'''
         
        transcript_instance.retained_introns=[]
        
        for exon in filter(lambda e: e not in transcript_instance.non_overlapping_cds, transcript_instance.exons):
            #Check that the overlap is at least as long as the minimum between the exon and the intron.
            if any(filter(
                          lambda junction: self.overlap(exon,junction)>=junction[1]-junction[0],
                          self.junctions                          
                          )) is True:
                    transcript_instance.retained_introns.append(exon)
        transcript_instance.retained_introns=tuple(transcript_instance.retained_introns)
            
    def load_scores(self, scores):
        '''Simple mock function to load scores for the transcripts from an external dictionary.
        '''
        
        for tid in self.transcripts:
            if tid in scores:
                self.transcripts[tid].score=scores[tid]
            else:
                self.transcripts[tid].score=0            
            
    def calculate_scores(self):
        '''
        Function to calculate a score for each transcript, given the metrics derived
        with the calculate_metrics method.
        The exact ordering must be provided from outside using a JSON file.
         
         '''
        
        self.get_metrics()
        
        for tid in self.transcripts:
            values = []
            for param in self.json_dict["parameters"]:
                x = getattr(self.transcripts[tid], param)
                if "expression" in self.json_dict["parameters"][param]:
                    try:
                        x = eval(self.json_dict["parameters"][param]["expression"] ) 
                    except ZeroDivisionError:
                        x = 0
                    except TypeError as err:
                        raise TypeError(str(err)+"\n"+str((x,param)))
                if "multiplier" in self.json_dict["parameters"][param]:
                    x*=self.json_dict["parameters"][param]["multiplier"]
                elif "bool_value" in self.json_dict["parameters"][param]:
                    assert type(x) is bool
                    if x is True:
                        x = self.json_dict["parameters"][param]["bool_value"][0]
                    else:
                        x = self.json_dict["parameters"][param]["bool_value"][1]
                #assert type(x) in (int,float), (param, x)
                values.append(x)
            score=sum(values)
            self.transcripts[tid].score=score
        
        not_passing = set()
        if "requirements" in self.json_dict:
            for key in self.json_dict["requirements"]:
                for tid in self.transcripts:
                    x=getattr(self.transcripts[tid],key)
                    #assert "expression" in self.json_dict["requirements"][key], key
                    if  eval(self.json_dict["requirements"][key]["expression"]) is False: not_passing.add(tid)
#                 if len(not_passing)==len(self.transcripts): #all transcripts in the locus fail to pass the filter
#                     continue
#                 else:
        for tid in not_passing:
            self.transcripts[tid].score=0
    
    def print_metrics(self):
        
        '''This class yields dictionary "rows" that will be given to a csv.DictWriter class.'''
        
        #Check that rower is an instance of the csv.DictWriter class
#        self.get_metrics()
        self.calculate_scores() 
        
        #The rower is an instance of the DictWriter class from the standard CSV module
        
        for tid in sorted(self.transcripts.keys(), key=lambda tid: self.transcripts[tid] ):
            row={}
            for key in self.available_metrics:
                if key.lower() in ("id", "tid"):
                    row[key]=tid
                elif key.lower()=="parent":
                    row[key]=self.id
                else:
                    row[key]=getattr(self.transcripts[tid], key, "NA")
                if type(row[key]) is float:
                    row[key] = round(row[key],2)
                elif row[key] is None or row[key]=="":
                    row[key]="NA"
            yield row
        return
    
    def get_metrics(self):
        
        '''Quick wrapper to calculate the metrics for all the transcripts.'''
        
        if self.metrics_calculated is True:
            return
        
        for tid in self.transcripts:
            self.calculate_metrics(tid)

        self.metrics_calculated = True
        return


    ############### Class methods ################

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
    
    ########### Properties
    
    @property
    def splitted(self):
        '''The splitted flag indicates whether a sublocus has already been processed to produce the necessary monosubloci.
        It must be set as a boolean flag (hence why it is coded as a property)'''
        return self.__splitted
    
    @splitted.setter
    def splitted(self,verified):
        if type(verified)!=bool:
            raise TypeError()
        self.__splitted=verified
        
    @property
    def id(self):
        if self.monoexonic is True:
            addendum = "mono"
        else:
            addendum = "multi"
        
        return "{0}.{1}".format(super().id, addendum)
    
#     @property
#     def available_metrics(self):
# #         if self.__available_metrics == []:
# #             self.__available_metrics = self.get_metrics()
#             
#         return self.__available_metrics
#     
#     @available_metrics.setter
#     def available_metrics(self, arg):
#         if type(arg) is not list:
#             raise ValueError("Invalid value for the metrics: {0}, type {1}".format(
#                                                                                    arg,
#                                                                                    type(arg)
#                                                                                    ))     
#         self.__available_metrics = arg
        
        
        
        
        