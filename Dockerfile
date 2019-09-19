FROM nfcore/base
LABEL authors="Maxime Garcia, Szilveszter Juhos" \
      description="Docker image containing all requirements for nf-core/sarek pipeline"

COPY environment.yml /
RUN conda env create -f /environment.yml && conda clean -a
ENV PATH /opt/conda/envs/nf-core-sarek-2.5/bin:$PATH
