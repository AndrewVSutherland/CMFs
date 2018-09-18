from sage.all import  vector, PolynomialRing, ZZ, NumberField, parallel
import os, sys
os.chdir('/home/edgarcosta/lmfdb/')
sys.path.append('/home/edgarcosta/lmfdb/')
from  lmfdb.db_backend import db
ZZx = PolynomialRing(ZZ, "x")
def convert_eigenvals_to_qexp(basis, eigenvals):
    qexp = [0]
    for i, ev in enumerate(eigenvals):
        if ev['n'] != i+1:
            raise ValueError("Missing eigenvalue")
        if 'an' in ev:
            an = sum(elt * basis[i] for i, elt in enumerate(ev['an']))
            qexp.append(an)
        else:
            raise ValueError("Missing eigenvalue")
    return qexp


@parallel(ncpus = 40)
def upsert_embedding(rowcc):
    row_embeddings =  {}
    hecke_orbit_code = rowcc['hecke_orbit_code']
    newform = db.mf_newforms.lucky({'hecke_orbit_code':hecke_orbit_code})
    if newform['dim'] == 1:
        row_embeddings['embedding_root_imag'] = 0
        row_embeddings['embedding_root_real'] = 0
    elif newform.get('field_poly', None) is None:
	return
    else:
        print rowcc['lfunction_label']
        HF = NumberField(ZZx(newform['field_poly']), "v")
        numerators =  newform['hecke_ring_numerators']
        denominators = newform['hecke_ring_denominators']
        betas = [HF(elt)/denominators[i] for i, elt in enumerate(numerators)]

        row_hecke_nf = db.mf_hecke_nf.lucky({'hecke_orbit_code':hecke_orbit_code})
        embeddings = HF.complex_embeddings(prec=2000)
        an_nf = list(db.mf_hecke_nf.search({'hecke_orbit_code':hecke_orbit_code}, ['n','an'], sort=['n']))
        betas_embedded = [map(elt, betas) for elt in embeddings]
        CCC = betas_embedded[0][0].parent()
        qexp = [convert_eigenvals_to_qexp(elt, an_nf) for elt in betas_embedded]
        min_len = min(len(rowcc['an']), len(qexp[0]))
        an_cc = vector(CCC, map(lambda x: CCC(x[0], x[1]), rowcc['an'][:min_len]))
        #qexp_diff = [ (vector(CCC, elt[:min_len]) - an_cc).norm() for elt in qexp ]
        # normalized, to avoid the unstability comming from large weight
        qexp_diff = [ vector([(elt- an_cc[i])/elt.abs() for i, elt in enumerate(q) if elt != 0]).norm()   for j,q in enumerate(qexp)]

        qexp_diff_sorted = sorted(qexp_diff)
        min_diff = qexp_diff_sorted[0]
        print "min_diff = %.2e \t min_diff/2nd = %.2e" % (min_diff, min_diff/qexp_diff_sorted[1])

        #assuring that is something close to zero, and that no other value is close to it
        assert min_diff < 1e-6
        assert min_diff/qexp_diff_sorted[1] < 1e-15

        for i, elt in enumerate(qexp_diff):
            if elt == min_diff:
                row_embeddings['embedding_root_real'] = embeddings[i](HF.gen()).real()
                row_embeddings['embedding_root_imag'] = embeddings[i](HF.gen()).imag()
                break
    assert len(row_embeddings) == 2
    db.mf_hecke_cc.upsert({'id': rowcc['id']}, row_embeddings)


upsert_embedding(db.mf_hecke_cc.search({'embedding_root_real':None}, projection=['an', 'hecke_orbit_code','id','lfunction_label']))
