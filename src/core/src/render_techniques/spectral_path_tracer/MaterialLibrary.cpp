
#include "Medium.h"
#include "load_mpml.h"
#include "Interface.h"
#include "glass.h"
#include "MaterialLibrary.h"

#include "gpu_shared.h"

using namespace std;

typedef map<string, Medium>::iterator mat_it;
typedef map<string, Interface>::iterator int_it;

float3 color_to_float3(Color<double> & color)
{
	return float3(static_cast<float>(color[0]),static_cast<float>(color[1]),static_cast<float>(color[2]));
}

void convert_mediums(Medium & medium, MPMLMedium & new_medium)
{
	medium.fill_rgb_data();
	new_medium.name =				medium.name;
	new_medium.absorption =			color_to_float3(medium.get_absorption(rgb));
	new_medium.albedo =				color_to_float3(medium.get_albedo(rgb));
	new_medium.asymmetry =			color_to_float3(medium.get_asymmetry(rgb));
	//new_medium.emission =			color_to_float3(medium.get_emission(rgb));
	new_medium.extinction =			color_to_float3(medium.get_extinction(rgb));
	new_medium.reduced_albedo =		color_to_float3(medium.get_reduced_alb(rgb));
	new_medium.reduced_extinction = color_to_float3(medium.get_reduced_ext(rgb));
	new_medium.reduced_scattering = color_to_float3(medium.get_reduced_sca(rgb));
	new_medium.scattering =			color_to_float3(medium.get_scattering(rgb));
	Color<std::complex<double>> ior =	medium.get_ior(rgb);
	new_medium.ior_real = float3(static_cast<float>(ior[0].real()), static_cast<float>(ior[1].real()), static_cast<float>(ior[2].real()));
	new_medium.ior_imag = float3(static_cast<float>(ior[0].imag()), static_cast<float>(ior[1].imag()), static_cast<float>(ior[2].imag()));
}

void load_mpml(const string & filename, map<string, MPMLMedium>& lMedia, map<string, Medium>& full_media, map<string, MPMLInterface>& interface_map)
{
	map<string, Medium> media_old;
	map<string, Interface> lInterfaces;
	load_mpml(filename,media_old,lInterfaces);

	for(mat_it iterator = media_old.begin(); iterator != media_old.end(); iterator++) {
		string name = iterator->first;

		Medium med = iterator->second;
		med.fill_rgb_data();
		MPMLMedium * mat = new MPMLMedium();
		convert_mediums(med,*mat);
		lMedia[name] = *mat;
		full_media[name] = med;
	}

	for(int_it iterator_interf = lInterfaces.begin(); iterator_interf != lInterfaces.end(); iterator_interf++) {
		string name = iterator_interf->first;
		Interface intef = iterator_interf->second;
		MPMLInterface * new_interface = new MPMLInterface();
		new_interface->name = name;
		if(intef.med_in && lMedia.count(intef.med_in->name) != 0)
			new_interface->med_in = &(lMedia.at(intef.med_in->name));
		if(intef.med_out && lMedia.count(intef.med_out->name) != 0)
			new_interface->med_out = &(lMedia.at(intef.med_out->name));
		interface_map[name] = *new_interface;
	}
}

void get_relative_ior(const MPMLMedium & med_in, const MPMLMedium & med_out, float3 & eta, float3 & kappa)
{
	const float3& eta1 = med_in.ior_real;
	const float3& eta2 = med_out.ior_real;
	const float3& kappa1 = med_in.ior_imag;
	const float3& kappa2 = med_out.ior_imag;

	float3 ab = (eta1 * eta1 + kappa1 * kappa1);
	eta = (eta2 * eta1 + kappa2 * kappa1)/ab;
	kappa = (eta1 * kappa2 - eta2 * kappa1)/ab;
}

map<string, MPMLInterface> MaterialLibrary::interfaces = map<string, MPMLInterface>();
map<string, MPMLMedium> MaterialLibrary::media = map<string, MPMLMedium>();
map<string, Medium> MaterialLibrary::full_media = map<string, Medium>();

void MaterialLibrary::convert_and_store(Medium m)
{
	MPMLMedium * new_medium = new MPMLMedium();
	convert_mediums(m, *new_medium);
	media[m.name] = *new_medium;
	full_media[m.name] = m; 
}

void MaterialLibrary::load(const char * mpml_path)
{
	load_mpml(mpml_path,media, full_media, interfaces);
	Medium air;
	air.get_ior(mono).resize(1);
	air.get_ior(mono)[0] = complex<double>(1.0, 0.0);
	air.fill_rgb_data();
	air.name = "air";
	air.turbid = false;
	MPMLMedium * air_converted = new MPMLMedium();
	convert_mediums(air,*air_converted);
	media["air"] = *air_converted;

	convert_and_store(deep_crown_glass());	
	convert_and_store(crown_glass());
	convert_and_store(crown_flint_glass());
	convert_and_store(light_flint_glass());
	convert_and_store(dense_barium_flint_glass());
	convert_and_store(dense_flint_glass());
}

