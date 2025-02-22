import sqlite3
import os
import sys
import struct
import json

from dirichlet_conrey import *
from sage.all import prime_range, pi
from sage.databases.cremona import cremona_letter_code, class_to_int

to_compute = 2000 #coeffs/traces that we compute
to_store = 1000  # that we store


# folders
import socket
hostname = socket.gethostname()
assert hostname in ['saint-germain', 'LEGENDRE']
base_export = None
base_import = None
if hostname == 'LEGENDRE':
    base_export = "/scratch/importing/CMF"
    base_import = "/scratch/home/bober"
elif hostname == 'saint-germain':
    base_import = "/home/edgarcosta/bober"
    base_export = "/home/edgarcosta/export/CMF"
else:
    sys.exit("hostname = %s" % hostname)


def index_above(n, k ,c):
    if c == 1:
        return n**k, 1
    if c == n - 1 and  (n % 2 == 1 or n % 4 == 0):
        return n**k, n**k - 1
    else:
        # DirichletGroup_conrey is too slow!
        return n, c

import subprocess
def call_index_above(n, k, c):
    cmd = ["sage", "-python","/home/edgarcosta/CMFs/ccscripts/index.py"]+ map(str, [n, k, c])
    pipes = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    std_out, std_err = pipes.communicate()
    if pipes.returncode != 0:
        N, C = n, c
    else:
        # a bit stupid but assures that we don't read junk
        N, C = map(int, std_out.split('\n')[-2].split('.'))
    return '%s.%s' % (n, c)

####################
# postgres stuff
###################


default_type = 'CMF'

def constant_lf(level, weight, degree):
    assert degree % 2 == 0
    output =  {
        'primitive' : 't' if degree == 2 else 'f', 
        'conductor' : level**(degree//2),
        'load_key' : 'CMFs-workshop',
        'motivic_weight': weight - 1,
        'types': str([default_type]).replace("'","\""),
        'symmetry_type': '\N',
        'group' : 'GL2',
        'degree' : degree,
        'st_group' : '\N',
        'selfdual': '\N',
        'analytic_normalization': float(weight - 1)/2,
        'precision': '\N',
        'algebraic': 't',
        'coeff_info': '\N', #FIXME
        'credit' : '\N',
        'values': '\N', # no special values at the moment
        'gamma_factors': [[], [0]*(degree//2)],
        'coefficient_field': '\N', # the label of the Hecke field, we set as \N as start
        'dirichlet_coefficients' : '\N', # we already store a2 .. a10
        'trace_hash': '\N'
        }
    for i in range(2,11):
        output['A' + str(i)] = '\N'

    return output

schema_lf = [
        'load_key', # 'CMFs'
        'origin', # ModularForm/GL2/Q/holomorphic/N/k/chi/a/n
        'primitive', # True
        'conductor', # N
        'central_character', # N.chi
        'self_dual',  # boolean, Bober tells me
        'motivic_weight', # k - 1
        'conjugate', # Bober tells me
        'types', # ['MF']
        'Lhash', # first zero: str(<first zero of L_0> * 2^100).round())
        'symmetry_type', # 'unitary' or 'orthogonal' or 'symplectic'  FIXME: delete?
        'group', # GL2
        'degree', # 2
        'st_group', # unkown for the moment
        'plot_delta', # numeric,
        'selfdual', # to be removed
        'analytic_normalization', # (k - 1)/2<D-f>
        'euler_factors', # as polys
        'z1', #first zero
        'z2', #2nd zero
        'z3', #3rd zero
        'precision', # this is only used for mass forms, might mean the precision of the eigenvalue in that case
        'accuracy', # bit accuracy (after the decimal point) of the nontrivial zeros
        'order_of_vanishing', # int
        'bad_lfactors', # Null for the moment
        'sign_arg', # muti valued denoting the angle
        'plot_values', # list of doubles
        'algebraic', # True
        'coeff_info', # ???? ,
        'leading_term', # WARNING is text
        'root_number', # WARNING text
        'positive_zeros', #list of doubles
        'credit', # empty string
        'gamma_factors', # jsonb,
        'values', # special values, format???
        'dirichlet_coefficients', # the ap as algebraic numbers or complex
        'coefficient_field', # the label of the Hecke field
        'trace_hash'
        ]
for i in range(2,11):
    schema_lf.append('A'+ str(i))
    schema_lf.append('a' + str(i))


    schema_lf_dict = dict([ (key, i) for i, key in enumerate(schema_lf)])

schema_lf_types = {u'A10': u'numeric',
     u'A2': u'numeric',
     u'A3': u'numeric',
     u'A4': u'numeric',
     u'A5': u'numeric',
     u'A6': u'numeric',
     u'A7': u'numeric',
     u'A8': u'numeric',
     u'A9': u'numeric',
     u'Lhash': u'text',
     u'a10': u'jsonb',
     u'a2': u'jsonb',
     u'a3': u'jsonb',
     u'a4': u'jsonb',
     u'a5': u'jsonb',
     u'a6': u'jsonb',
     u'a7': u'jsonb',
     u'a8': u'jsonb',
     u'a9': u'jsonb',
     u'accuracy': u'smallint',
     u'algebraic': u'boolean',
     u'analytic_normalization': u'numeric',
     u'bad_lfactors': u'jsonb',
     u'central_character': u'text',
     u'coeff_info': u'jsonb',
     u'coefficient_field': u'text',
     u'conductor': u'numeric',
     u'conjugate': u'text',
     u'credit': u'text',
     u'degree': u'smallint',
     u'dirichlet_coefficients': u'jsonb',
     u'euler_factors': u'jsonb',
     u'gamma_factors': u'jsonb',
     u'group': u'text',
     u'id': u'bigint',
     u'leading_term': u'text',
     u'load_key': u'text',
     u'motivic_weight': u'smallint',
     u'order_of_vanishing': u'smallint',
     u'origin': u'text',
     u'plot_delta': u'numeric',
     u'plot_values': u'jsonb',
     u'positive_zeros': u'jsonb',
     u'precision': u'smallint',
     u'primitive': u'boolean',
     u'root_number': u'text',
     u'self_dual': u'boolean',
     u'selfdual': u'boolean',
     u'sign_arg': u'numeric',
     u'st_group': u'text',
     u'symmetry_type': u'text',
     u'types': u'jsonb',
     u'values': u'jsonb',
     u'z1': u'numeric',
     u'z2': u'numeric',
     u'z3': u'numeric',
     'trace_hash': 'bigint'}

schema_lf_types.pop('id')

for key in schema_lf_types.keys():
    assert key in schema_lf
for key in schema_lf:
    assert key in schema_lf_types, '%s not in schema_lf_types' % key



schema_instances = ['url', 'Lhash', 'type']

schema_instances_types = {u'Lhash': u'text', u'id': u'bigint', u'type': u'text', u'url': u'text'}
schema_instances_types.pop('id')


######################
# End of postgres stuff
########################


# sqrt hack for ComplexBallField
def sqrt_hack(foo):
    if not foo.real().contains_zero() and foo.real().mid() < 0:
        return foo.parent().0*(-foo).sqrt()
    else:
        return foo.sqrt()

def arg_hack(foo):
    if not foo.real().contains_zero() and foo.real().mid() < 0:
        arg = (-foo).arg()
        #print arg
        if arg > 0:
            arg -= foo.parent().pi().real()
        else:
            arg += foo.parent().pi().real()
        return arg
    else:
        return foo.arg()

# other globals
CCC = ComplexBallField(2000)
RRR = RealIntervalField(2000)

def CBFlistcmp(L1, L2):
    for (z1, z2) in zip(L1, L2):
        x1, y1 = z1.real(), z1.imag()
        x2, y2 = z2.real(), z2.imag()
        if x1 < x2:
            return -1r
        elif x1 > x2:
            return 1r
        elif y1 < y2:
            return -1r
        elif y1 > y2:
            return 1r

    return 0r

def CBFlisteq(L1, L2):
    for (z1, z2) in zip(L1, L2):
        if not (z1 - z2).contains_zero():
            return False
    return True


def CBFcmp(z1, z2):
    x1, y1 = z1.real(), z1.imag()
    x2, y2 = z2.real(), z2.imag()

    if x1 < x2:
        return -1
    elif x1 > x2:
        return 1
    elif y1 < y2:
        return -1
    elif y2 < y1:
        return 1

    return 0


MF_PREC_EXACT = 2147483647

def extend_multiplicatively(Z):
    for pp in prime_powers(len(Z)-1):
        for k in range(1, (len(Z) - 1)//pp + 1):
            if gcd(k, pp) == 1:
                Z[pp*k] = Z[pp]*Z[k]

def read_gmp_int(buf, offset):
    length = struct.unpack_from('>i', buf, offset)[0]
    bytes_read = 4
    sign = 1
    if length < 0:
        sign = -1
        length = -length
    if length > 10000: #something has probably gone wrong
        return
    limb_fmt = '{}B'.format(length)
    data = struct.unpack_from(limb_fmt, buf, offset + bytes_read)
    bytes_read = bytes_read + struct.calcsize(limb_fmt)
    number = sign*sum((x*2**(8*k) for (k,x) in enumerate(reversed(data))))
    return number, bytes_read

def read_orbit(orbitblob):
    A = struct.unpack_from('i'*(len(orbitblob)/4r), orbitblob)
    return [ (A[2*i], A[2*i+1]) for i in range(len(A)/2r) ]

def RIF_to_float(x):
    x = RRR(x)
    if x.contains_zero():
        return 0
    else:
        return float(x)
def CBF_to_pair(x):
    a = CCC(x)
    return [RIF_to_float(a.real()), RIF_to_float(a.imag())]

def reciprocal_roots(coeff):
    if len(coeff) == 3:
        a, b ,c = coeff;
        sqrtdisc = sqrt_hack(b**2 - 4*a*c)
        alpha1 = (-b + sqrtdisc)/(2*a)
        alpha2 = (-b - sqrtdisc)/(2*a)
        return [alpha1, alpha2]
    elif len(coeff) == 2:
        a, b = coeff
        return [-b/a]

def from_power_sums(ps):
    assert ps[0] is None
    es = [None] * len(ps)
    es[0] = 1
    if len(ps) > 1:
        es[1] = ps[1]
        for k in range(2, len(ps)):
            es[k] = sum( (-1)^(i -1) * es[k-i] * ps[i] for i in range(1, k + 1))/k
        es = [(-1)^i * elt for i, elt in enumerate(es)]
    return es



def prod_plot_values(factor_plot_deltas, factor_values):
    assert len(factor_plot_deltas) == len(factor_values)
    halfdegree = len(factor_values)
    if halfdegree == 1:
        return factor_plot_deltas[0], factor_values[0]
    factor_plot_values = [ [ ( j * factor_plot_deltas[k],  z) for j, z in enumerate(values) ] for k, values in enumerate(factor_values)]
    interpolations = [spline(elt) for elt in factor_plot_values]
    max_delta = max(factor_plot_deltas)
    new_delta = max_delta/halfdegree
    plot_range = min( [elt[-1][0] for elt in factor_plot_values] )
    values = [prod([elt(i) for elt in interpolations]) for i in srange(0, plot_range, new_delta)]
    return new_delta, values

def rational_euler_factors(traces, euler_factors_cc, level, weight):
    dirichlet = [1]*11
    dirichlet[0] = 0
    euler_factors = []
    bad_lfactors = []
    halfdegree = len(euler_factors_cc)
    PS = PowerSeriesRing(ZZ, "X")
    CCCx = PolynomialRing(CCC, "x")
    x = CCCx.gen()
    todo = list(enumerate(primes_first_n(30)))
    for p in sorted(ZZ(level).prime_divisors()):
        p_index = prime_pi(p) - 1
        if p_index >= 30:
            todo.append((p_index, p))
    for p_index, p in todo:
        if p_index > len(euler_factors_cc[0]):
            assert level % p == 0
            bad_lfactors.append([int(p), [int(1)] + [None]*halfdegree])
            continue

        #try to guess the rest by multiplying them
        roots = []
        for lf in euler_factors_cc:
            roots += reciprocal_roots(lf[p_index])
        root_powers = [None] * (halfdegree + 1)
        for j in range(1,halfdegree + 1):
            try:
                root_powers[j] = RRR(sum( map(lambda z: (z^j).real(), roots) )).unique_integer()
            except ValueError:
                root_powers = root_powers[:j]
                break
        partial_efzz = from_power_sums(root_powers)
        efzz = map(int, partial_efzz) + [None]*(halfdegree +1 - len(partial_efzz))
        if len(traces) > p:
            if efzz[1] is None:
                efzz[1] = int(-traces[p - 1])
            else:
                assert efzz[1] == -traces[p - 1]

        # to check that from_power_sums is correct
        ef = prod([CCCx(lf[p_index]) for lf in euler_factors_cc])
        for j, elt in enumerate(ef.list()[:len(partial_efzz)]):
            try:
                efj = RRR(elt.real()).unique_integer()
            except ValueError:
                break;
            assert efj == efzz[j]


        if level % p != 0:
            sign = RRR(ef.list()[-1].real()/p^((halfdegree)*(weight - 1))).unique_integer()
            assert sign in [1,-1], "%s\n%s" % (RRR(prod( lf[p_index][2] for lf in euler_factors_cc).real()).unique_integer(),p^((halfdegree)*(weight - 1)))
            efzz2 = [None] * halfdegree
            for i, elt in enumerate(reversed(efzz[:-1])):
                if elt is None:
                    efzz2[i] = None
                else:
                    efzz2[i] = int(sign*p^((i+1)*(weight - 1)) * elt)
            efzz += efzz2
            euler_factors.append(efzz)
        else:
            if None not in efzz:
                k = len(efzz)
                while efzz[k - 1] == 0 and k >= 1:
                    k -= 1
                efzz = efzz[:k]
            bad_lfactors.append([int(p), efzz])
            if p_index < 30:
                euler_factors.append(efzz)
        if p < 11:
            if p == 2:
                foo = (1/PS(efzz[:4])).padded_list(4)
                for i in range(1, 4):
                    dirichlet[p**i] = foo[i]
            elif p == 3:
                foo = (1/PS(efzz[:3])).padded_list(4)
                for i in range(1, 3):
                    dirichlet[p**i] = foo[i]
            else:
                dirichlet[p] = -efzz[1] if len(efzz) > 1 else 0;
            assert dirichlet[p] == traces[p-1], "p = %s, ap = %s, tp = %s, efzz = %s" % (p, dirichlet[p], traces[p-1], efzz)

        extend_multiplicatively(dirichlet)




    assert len(euler_factors) == 30

    return euler_factors, bad_lfactors, dirichlet

def angles_euler_factors(coeffs, level, weight, chi):
    """
    - ``coeffs`` -- a list of Dirichlet coefficients, as elements of CCC
    - ``level`` -- the level N
    - ``weight`` -- the weight k
    - ``chi`` -- the index of the Dirichlet character in the Conrey labeling
    returns a triple: (angles, euler_factos, bad_euler_factors)
    """
    G = DirichletGroup_conrey(level, CCC)
    char = DirichletCharacter_conrey(G, chi)
    euler = []
    bad_euler = []
    angles = []
    for p in prime_range(to_store):
        b = -coeffs[p]
        c = 1
        if p.divides(level):
            bad_euler.append([p, [c, b]])
            euler.append([c,b])
            a = 0
        else:
            charval = CCC(2*char.logvalue(p)).exppii()
            if charval.contains_exact(1):
                charval = 1
            elif charval.contains_exact(-1):
                charval = -1
            a = (p**(weight-1))*charval
            euler.append([c,b,a])
            # alpha solves T^2 - a_p T + chi(p)*p^(k-1)
            sqrt_disc = sqrt_hack(b**2 - 4*a*c)
            thetas = []
            for sign in [1, -1]:
                alpha = (-b + sign * sqrt_hack(b**2 - 4*a*c))/(2*c)
                theta = (arg_hack(alpha) / (2*CCC.pi().real())).mid()
                if theta > 0.5:
                    theta -=1
                elif theta <= -0.5:
                    theta +=1
                assert theta <= 0.5 and theta > -0.5, "%s %s %s" % (theta, arg_hack(alpha), alpha)
                thetas.append(theta)
            angles.append([p, float(min(thetas))])
        if len(coeffs) > p**2:
            assert (coeffs[p**2] -(b**2 - a)).abs().mid() < 1e-5, "(level, weight, chi, p) = %s\n%s != %s\na_p2**2 -  (b**2 - a)= %s\n b**2  - a = %s\na_p2 = %s" % ((level, weight, chi, p), CDF(coeffs[p**2]), CDF(b**2 - a), coeffs[p**2] -(b**2 - a), b**2 - a, coeffs[p**2])
    an_f = map(CBF_to_pair, coeffs[:to_store + 1])
    return an_f, angles, euler, bad_euler


def write_header(lfunctions_filename, instances_filename, overwrite = False):

    str_parsing_lf = '\t'.join(['%s'] * len(schema_lf)) + '\n'
    str_parsing_instances = '\t'.join(['%s'] * len(schema_instances)) + '\n'
    if not os.path.exists(lfunctions_filename) or overwrite:
        with open(lfunctions_filename,"w") as F:
            F.write(str_parsing_lf % tuple(schema_lf))
            F.write(str_parsing_lf % tuple([schema_lf_types[key] for key in schema_lf]))
            F.write("\n")

    if not os.path.exists(instances_filename):
        with open(instances_filename, "w") as F:
            F.write(str_parsing_instances % tuple(schema_instances))
            F.write(str_parsing_instances % tuple([schema_instances_types[key] for key in schema_instances]))
            F.write("\n")


def write_header_hecke_file(filename, overwrite = False):
    columns = ['hecke_orbit_code', 'lfunction_label', 'conrey_label', 'embedding_index', 'embedding_m', 'embedding_root_real', 'embedding_root_imag', 'an', 'first_an', 'angles', 'first_angles']
    types = ['bigint', 'text', 'integer', 'integer', 'integer', 'double precision', 'double precision', 'jsonb', 'jsonb', 'jsonb', 'jsonb']
    if not os.path.exists(filename) or overwrite:
        with open(filename, "w") as FILE:
            FILE.write("\t".join(columns) + "\n")
            FILE.write("\t".join(types) + "\n")
            FILE.write("\n")

@parallel(ncpus=48)
def do(level, weight, char_index):
    print "N = %s, k = %s, orbit_index = %s" % (level, weight, char_index)
    mfdbinfile = os.path.join(base_import, 'mfdb/{}.{}.mfdb'.format(level, weight))

    traces_filename = os.path.join(base_export, 'CMF_traces_MISSING.txt')

    def write_traces(traces_filename):
        with open(traces_filename, 'a') as F:
            F.write('{}:{}:{}:{}:{}\n'.format(level, weight, char_index, dim, traces[1:]).replace(' ',''))

    orbit_labels = {}
    G = DirichletGroup_conrey(level)
    orbits = G._galois_orbits()
    for k, orbit in enumerate(orbits):
        for chi in orbit:
            # we are starting at 1
            orbit_labels[chi] = k + 1
    if level == 1:
        k = 0
        orbit_labels = {1:1}


    mfdb = sqlite3.connect(os.path.join(mfdbinfile))
    mfdb.row_factory = sqlite3.Row

    '''
    expected schema:
        CREATE TABLE modforms (level INTEGER, weight INTEGER, chi INTEGER, orbit INTEGER, j INTEGER,
            prec INTEGER, exponent INTEGER, ncoeffs INTEGER, coefficients BLOB)
    '''
    coeffs = {}

    for result in mfdb.execute('SELECT prec, exponent, ncoeffs, coefficients, chi, j FROM modforms WHERE level={} AND weight={};'.format(level, weight)):
        chi = result['chi']
        chibar = inverse_mod(chi, level)
        if orbit_labels[chi] != char_index and orbit_labels[chibar] != char_index:
            continue

        is_trivial = False
        is_quadratic = False
        if chi == 1:
            is_trivial = True
        elif (chi*chi) % level == 1:
            is_quadratic = True

        j = result['j']
        offset = 0
        coeffblob = result['coefficients']
        exponent = result['exponent']
        prec = result['prec']
        # print prec, exponent
        _coeffs = [CCC(0)] * (to_compute + 1)
        #for k in range(35): # number of prime powers < 100
        for pp in prime_powers(to_compute):
            z, bytes_read = read_gmp_int(coeffblob, offset)
            #print z
            offset = offset + bytes_read
            real_part = CCC(z*2^exponent)
            if prec != MF_PREC_EXACT:
                real_part = real_part.add_error(2^prec)
            imag_part = 0
            if not is_trivial:
                z, bytes_read = read_gmp_int(coeffblob, offset)
                offset = offset + bytes_read
                imag_part = CCC(I*z*2^exponent)
                if prec != MF_PREC_EXACT:
                    imag_part = imag_part.add_error(2^prec)
            z = real_part + imag_part
            _coeffs[pp] = z
            #if not is_trivial and not is_quadratic:            # just for the moment...
            #    z = 2*real_part
            #traces[k] += z
        #print coeffs
        _coeffs[1] = CCC(1)
        extend_multiplicatively(_coeffs)
        coeffs[(chi, j)] = _coeffs
        if chibar > chi:
            coeffs[(chibar, j)] = [z.conjugate() for z in _coeffs]



    #mforbits = {}
    dim = 0
    traces_bound = to_compute + 1
    traces = [RRR(0)] * traces_bound
    for chi, j in coeffs.keys():
        if orbit_labels[chi] == char_index:
            dim += 1
            for k, z in enumerate(coeffs[(chi, j)][:traces_bound]):
                traces[k] += RRR(z.real())

    for i, z in enumerate(traces):
        try:
            traces[i] = z.unique_integer()
        except ValueError:
            traces = traces[:i]
            break;

    write_traces(traces_filename)
    return 0

    for key, val in labels.iteritems():
        print key,"  \t-new->\t", val
    for key, val in conjugates.iteritems():
        print key,"\t--c-->\t", val

    for key, val in all_the_labels.iteritems():
        print key," \t--->\t" + "\t".join( map(str, [val,hecke_orbit_code[key]]))



    def origin(chi, a, n):
        return "ModularForm/GL2/Q/holomorphic/%d/%d/%s/%s/%d/%d" % (level, weight, cremona_letter_code(orbit_labels[chi] - 1), a, chi, n)

    def rational_origin(chi, a):
        return "ModularForm/GL2/Q/holomorphic/%d/%d/%s/%s" % (level, weight, cremona_letter_code(orbit_labels[chi] - 1), a)

    def label(chi,j):
        return labels[(chi,j)]


    def self_dual(chi, a, n):
        return selfduals[(chi, a, n)]



    Lhashes = {}
    instances = {}
    # the function below assumes this order
    assert schema_instances == ['url', 'Lhash', 'type']
    def tuple_instance(row):
        return (row['origin'], row['Lhash'], default_type)

    real_zeros = {}
    rows = {}
    def populate_complex_row(Ldbrow):
        row = dict(constant_lf(level, weight, 2))
        chi = int(Ldbrow['chi'])
        j = int(Ldbrow['j'])
        chil, a, n = label(chi,j)
        assert chil == chi

        row['order_of_vanishing'] = int(Ldbrow['rank'])
        zeros_as_int = zeros[(chi,j)][row['order_of_vanishing']:]
        prec = row['accuracy'] = Ldbrow['zeroprec']
        two_power = 2**prec
        double_zeros = [float(z/two_power) for z in zeros_as_int]
        zeros_as_real = [RealNumber(z.str()+".")/two_power for z in zeros_as_int]
        real_zeros[(chi, a, n)] = zeros_as_real
        zeros_as_str = [ z.str(truncate=False) for z in zeros_as_real]
        for i, z in enumerate(zeros_as_str):
            assert float(z) == double_zeros[i]
            assert (RealNumber(z) * two_power).round() == zeros_as_int[i]

        row['positive_zeros'] = str(zeros_as_str).replace("'","\"")

        row['origin'] = origin(chi, a, n)
        row['central_character'] = "%s.%s" % (level, chi)
        row['self_dual'] = self_dual(chi, a, n)
        row['conjugate'] = None
        row['Lhash'] = str(zeros_as_int[0] * 2**(100-prec).round())
        if prec < 100:
            row['Lhash'] = '_' + row['Lhash']
        Lhashes[(chi, a, n)] = row['Lhash']
        row['sign_arg'] = float(Ldbrow['signarg']/(2*pi))
        for i in range(0,3):
            row['z' + str(i + 1)] = RealNumber(str(zeros_as_int[i]) + ".")/2**prec

        row['plot_delta'] = Ldbrow['valuesdelta']
        row['plot_values'] = [RDF(CDF(elt).real_part()) for elt in struct.unpack('{}d'.format(len(Ldbrow['Lvalues'])/8), Ldbrow['Lvalues'])]



        row['leading_term'] = '\N'
        if row['self_dual']:
            row['root_number'] = str(RRR(CDF(exp(2*pi*I*row['sign_arg'])).real()).unique_integer())
        else:
            row['root_number'] = str(CDF(exp(2*pi*I*row['sign_arg'])))
        #row['dirichlet_coefficients'] = [None] * 10
        #print label(chi,j)
        for i, ai in enumerate(coeffs[(chi, j)][2:12]):
            ai = CDF(ai)
            ai_jsonb = [ai.real_part(), ai.imag_part()]
            if i + 2 <= 10:
                row['a' + str(i+2)] = ai_jsonb
                # print 'a' + str(i+2), ai_jsonb
            #row['dirichlet_coefficients'][i] = ai_jsonb


        row['coefficient_field'] = 'CDF'

        # only 30
        row['euler_factors'] = map( lambda x : map(CBF_to_pair, x), euler_factors[(chi, j)][:30])
        row['bad_lfactors'] = map( lambda x: [x[0], map(CBF_to_pair, x[1])], bad_euler_factors[(chi, j)])

        for key in schema_lf:
            assert key in row, "%s not in row = %s" % (key, row)
        assert len(row) == len(schema_lf), "%s != %s" % (len(row) , len(schema_lf))

        #rewrite row as a list
        rows[(chi, a, n)] = [row[key] for key in schema_lf]
        instances[(chi, a, n)] = tuple_instance(row)

    def populate_complex_rows():
        for key, row in Ldbresults.iteritems():
            populate_complex_row(row)


    def populate_conjugates():
    #    print Lhashes.keys()
        for key, row in rows.iteritems():
    #        print "key = %s" % (key,)
            row[schema_lf_dict['conjugate']] = Lhashes[conjugates[key]]
            row_conj = rows[conjugates[key]]
            zero_val_conj = row_conj[schema_lf_dict['plot_values']][0]
            assert (row[schema_lf_dict['plot_values']][0] - zero_val_conj) < 1e-10, "%s, %s: %s - %s = %s" % (key,conjugates[key], row[schema_lf_dict['plot_values']][0], zero_val_conj, row[schema_lf_dict['plot_values']][0]  - zero_val_conj)
            diff = (row[schema_lf_dict['sign_arg']] + row_conj[schema_lf_dict['sign_arg']]) % 1
            assert  min(diff,1 - diff) < 1e-10, "%s  + %s  = %s" % (row[schema_lf_dict['sign_arg']], row_conj[schema_lf_dict['sign_arg']], diff)

    rational_rows = {}
    def populate_rational_rows():
        CCCx = PolynomialRing(CCC, "x")
        order_of_vanishing = schema_lf_dict['order_of_vanishing']
        accuracy = schema_lf_dict['accuracy']
        positive_zeros = schema_lf_dict['positive_zeros']
        sign_arg = schema_lf_dict['sign_arg']
        Lhash = schema_lf_dict['Lhash']
        plot_delta = schema_lf_dict['plot_delta']
        plot_values = schema_lf_dict['plot_values']
        central_character = schema_lf_dict['central_character']
        # reverse euler factors from the table for  p^d < 1000
        rational_keys = {}
        for chi, a, n in rows.keys():
            orbit_label = orbit_labels[chi]
            if (orbit_label, a) not in rational_keys:
                rational_keys[(orbit_label, a)] = []
            rational_keys[(orbit_label, a)].append(  (chi, a, n) )


        for (orbit_label, a), triples in rational_keys.iteritems():
            # for now skip degree >= 100
            if len(triples) > 80: # the real limit is 87
                continue
            pairs = [ original_pair[elt] for elt in triples ]
            #print a, pairs, triples
            chi = triples[0][0]
            degree = 2*len(triples)
            row = constant_lf(level, weight, degree)
            row['origin'] = rational_origin(chi, a)
            print row['origin']
            row['self_dual'] = 't'
            row['conjugate'] = '\N'
            row['order_of_vanishing'] = sum([rows[elt][order_of_vanishing] for elt in triples])
            row['accuracy'] = min([rows[elt][accuracy] for elt in triples])


            ###
            zeros_as_real = []
            for elt in triples:
                zeros_as_real.extend( real_zeros[elt] )
            zeros_as_real.sort()
            zeros_as_str = [ z.str(truncate=False) for z in zeros_as_real]
            row['positive_zeros'] = str(zeros_as_str).replace("'","\"")
            zeros_hash = sorted([ (rows[elt][Lhash], real_zeros[elt][0]) for elt in triples], key = lambda x : x[1])
            row['Lhash'] = ",".join([elt[0] for elt in zeros_hash])
            # character
            if degree == 2:
                row['central_character'] = rows[triples[0]][central_character]
            else:
                G = DirichletGroup_conrey(level)
                chiprod = prod([G[ int(rows[elt][central_character].split(".")[-1]) ] for elt in triples])
                chiprod_index = chiprod.number()
                row['central_character'] = "%s.%s" % (level, chiprod_index)

            row['sign_arg'] = sum([rows[elt][sign_arg] for elt in triples])
            while row['sign_arg'] > 0.5:
                row['sign_arg'] -= 1
            while row['sign_arg'] <= -0.5:
                row['sign_arg'] += 1
            zeros_zi = []
            for i in range(0,3):
                for elt in triples:
                    zeros_zi.append(rows[elt][schema_lf_dict['z' + str(i + 1)]])
            zeros_zi.sort()
            for i in range(0,3):
                row['z' + str(i + 1)] = zeros_zi[i]

            deltas = [rows[elt][plot_delta] for elt in triples]
            values = [rows[elt][plot_values] for elt in triples]
            row['plot_delta'], row['plot_values'] = prod_plot_values(deltas, values)
            row['leading_term'] = '\N'
            row['root_number'] = str(RRR(CDF(exp(2*pi*I*row['sign_arg'])).real()).unique_integer())
            row['coefficient_field'] = '1.1.1.1'

            for chi, _, _ in triples:
                if (level, weight, chi) in traces_lists:
                    for elt in  traces_lists[(level, weight, chi)]:
                        if set(elt[1]) <= set(pairs):
                            traces = elt[0]
                            break
                    else:
                        print pairs
                        print traces_lists[(level, weight, chi)]
                        assert False
                    break
            else:
                print pairs
                print traces_lists
                assert False



            euler_factors_cc = [euler_factors[elt] for elt in pairs]
            row['euler_factors'], row['bad_lfactors'], dirichlet = rational_euler_factors(traces, euler_factors_cc, level, weight)
            #handling Nones
            row['euler_factors'] = json.dumps(row['euler_factors'])
            row['bad_lfactors'] = json.dumps(row['bad_lfactors'])

            # fill in ai
            for i, ai in enumerate(dirichlet):
                if i > 1:
                    row['a' + str(i)] = dirichlet[i]
                    #print 'a' + str(i), dirichlet[i]


            for key in schema_lf:
                assert key in row, "%s not in row = %s" % (key, row.keys())
            for key in row.keys():
                assert key in schema_lf, "%s unexpected"  % key
            assert len(row) == len(schema_lf), "%s != %s" % (len(row) , len(schema_lf))

            #rewrite row as a list
            rational_rows[(orbit_label, a)] = [row[key] for key in schema_lf]
            instances[(orbit_label, a)] = tuple_instance(row)

            # if dim == 1, drop row
            if len(triples) == 1:
                rows.pop(triples[0])
                instances.pop(triples[0])














    def get_hecke_cc():
        # if field_poly exists then compute the corresponding embedding of the root
        # add the conrey label
        hecke_cc = {}
        for key, label in labels.iteritems():
            # key = (chi,j)
            # label = (chi, a, n)
            chi, a, n = label
            ol = cremona_letter_code(orbit_labels[chi] - 1)
            lfuntion_label = ".".join( map(str, [level, weight] + [ol, a, chi, n]))
            hecke_cc[key] = [
                    hecke_orbit_code[key],
                    lfuntion_label, # N.k.c.x.n
                    label[0], # conrey_label
                    label[2], # embedding_index
                    embedding_m[key],
                    '\N', # embedding_root_real
                    '\N', # embedding_root_imag
                    coeffs_f[key][1:],
                    coeffs_f[key][1:101],
                    angles[key],
                    [pair for pair in angles[key] if pair[0] < 100],
                    ]
        return hecke_cc

    def write_hecke_cc(hecke_filename):
        write_header_hecke_file(hecke_filename)
        with open(hecke_filename, 'a') as HF:
            for v in get_hecke_cc().values():
                HF.write("\t".join(map(json.dumps,v)) + "\n")



    def export_complex_rows(lfunctions_filename, instances_filename):
        write_header(lfunctions_filename, instances_filename)
        #str_parsing_lf = '\t'.join(['%r'] * len(schema_lf)) + '\n'
        #str_parsing_instances = '\t'.join(['%r'] * len(schema_instances)) + '\n'

        with open(lfunctions_filename, 'a') as LF:
            for key, row in rows.iteritems():
                LF.write("\t".join(map(json.dumps,row)) + "\n")

            for key, row in rational_rows.iteritems():
                LF.write("\t".join(map(json.dumps,row)) + "\n")
        with open(instances_filename, 'a') as IF:
            for key, row in instances.iteritems():
                IF.write("\t".join(map(json.dumps,row)) + "\n")


    populate_complex_rows()
    populate_conjugates()
    populate_rational_rows()
    
    export_complex_rows(lfun_filename, instances_filename)
    write_hecke_cc(hecke_filename)
    write_traces(traces_filename)
    return 0


import sys, time
def do_Nk2(Nk2, only_traces = False):
    todo = []
    for N in ZZ(Nk2).divisors():
        k = sqrt(Nk2/N)
        if k in ZZ and k > 1:
            if False: # (N,k) in [(780,2), (840,2)]:
                print "skipping N = %d k = %d" % (N , k)
            else:
                todo.append((N, k))

    lfun_filename = os.path.join(base_export, 'CMF_Lfunctions_%d.txt' % (Nk2))
    instances_filename = os.path.join(base_export, 'CMF_instances_%d.txt' % (Nk2))
    hecke_filename = os.path.join(base_export, 'CMF_hecke_cc_%d.txt' % (Nk2))
    traces_filename = os.path.join(base_export, 'CMF_traces_%d.txt' % (Nk2))
    for F in [lfun_filename, instances_filename, hecke_filename, traces_filename]:
        if os.path.exists(F):
            os.remove(F)
    start_time = time.time()
    for i, (N, k) in enumerate(todo):
        do_time = time.time()
        do(N,k, lfun_filename, instances_filename, hecke_filename, traces_filename, only_traces)
        print "done, N = %s, k = %s" % (N, k)
        now = time.time()
        print "Progress: %.2f %%" % (100.*i/len(todo))
        print "Timing: %.2f\nTotal: %.2f\n\n" % (now - do_time, now- start_time)
        sys.stdout.flush()


print list(do(map(tuple, [[79, 12, 7], [81, 11, 8], [81, 12, 7], [83, 8, 3], [83, 9, 4], [83, 10, 3], [83, 11, 4], [83, 12, 3], [88, 12, 15], [89, 9, 8], [89, 11, 8], [92, 12, 8], [95, 11, 17], [95, 12, 18], [97, 11, 12], [97, 12, 11]])));



# Things to be set after uploading data:
# Lfunctions:
# - Coefficient field ?
# mf_hecke_cc
# - embedding_root_real
# - embedding_root_imag
# mf_newforms:
# - analytic rank from one of the Lfunctions

